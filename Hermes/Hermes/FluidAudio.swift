import Foundation
import AVFoundation
import Combine
@preconcurrency import FluidAudio

class FluidAudio: ObservableObject {
    static let shared = FluidAudio()
    
    @Published var transcript: String = ""
    @Published var status: String = "Initializing..."
    @Published var isModelReady: Bool = false
    
    private var asrManager: AsrManager?
    
    init() {
        Task {
            await setup()
        }
    }
    
    @MainActor
    private func setup() async {
        do {
            self.status = "Downloading models..."
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            
            self.status = "Initializing engine..."
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            
            self.asrManager = manager
            self.isModelReady = true
            self.status = "Ready (Parakeet TDT)"
            print("FluidAudio initialized successfully")
        } catch {
            self.status = "Error: \(error.localizedDescription)"
            print("FluidAudio initialization error: \(error)")
        }
    }
    
    // MARK: - Chunk Transcription
    
    /// Transcribe a completed audio chunk. Returns the transcribed text.
    /// This is the core method for the queue-based pipeline.
    func transcribeChunk(samples: [Float]) async -> String {
        guard let manager = asrManager else {
            print("[Hermes.ASR] Cannot transcribe — model not ready")
            return ""
        }
        
        do {
            let result = try await manager.transcribe(samples, source: .system)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[Hermes.ASR] Chunk transcribed: '\(text.prefix(80))' length=\(text.count)")
            return text
        } catch {
            print("[Hermes.ASR] Chunk transcription error: \(error)")
            return ""
        }
    }
    
    // MARK: - Live Preview (optional, runs during recording)
    
    private var isTranscribing = false
    private var pendingSamples: [Float]?
    private var isStopped = true
    
    func prepareForNewSession() {
        isStopped = false
        isTranscribing = false
        pendingSamples = nil
    }
    
    func startSession() async {
        await MainActor.run {
            self.transcript = ""
        }
    }
    
    func stopSession() {
        isStopped = true
        pendingSamples = nil
    }
    
    /// Live transcription of the current audio buffer for overlay preview.
    /// This updates `self.transcript` but is NOT used for injection.
    func transcribeLive(samples: [Float]) {
        guard isModelReady, !isStopped, let asrManager = asrManager else { return }
        
        if isTranscribing {
            pendingSamples = samples
            return
        }
        
        isTranscribing = true
        
        Task {
            do {
                let result = try await asrManager.transcribe(samples, source: .system)
                if !self.isStopped {
                    await MainActor.run {
                        if !result.text.isEmpty {
                            self.transcript = result.text
                        }
                    }
                }
            } catch {
                // Silently ignore live preview errors
            }
            
            self.isTranscribing = false
            if !self.isStopped, let pending = self.pendingSamples {
                self.pendingSamples = nil
                self.transcribeLive(samples: pending)
            }
        }
    }
}
