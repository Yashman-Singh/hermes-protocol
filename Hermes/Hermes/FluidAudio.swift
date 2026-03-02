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
    private var isTranscribing = false
    private var pendingSamples: [Float]?
    private var isStopped = true  // Prevents late transcription results after stop
    
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
    
    /// Reset critical flags synchronously so audio callbacks are accepted immediately.
    /// Called from AudioService.startRecording() BEFORE the audio engine starts.
    func prepareForNewSession() {
        isStopped = false
        isTranscribing = false
        pendingSamples = nil
    }
    
    func start() async throws {
        // Reset transcript on MainActor (cosmetic — UI update)
        await MainActor.run {
            self.transcript = ""
        }
        print("[Hermes.ASR] start() — session reset")
    }
    
    func stop() {
        // Mark as stopped FIRST — this prevents any in-flight or pending
        // transcriptions from updating the transcript after we capture it.
        isStopped = true
        pendingSamples = nil
        
        let textToRefine = self.transcript
        print("[Hermes.ASR] stop() — captured transcript='\(textToRefine.prefix(50))' length=\(textToRefine.count)")
        
        // Call refine synchronously — this is already on MainActor
        // (called from HotKeyManager → AudioService.stopRecording).
        // Synchronous call ensures isRefining = true is set BEFORE
        // isRecordingState = false, keeping the overlay visible.
        LLMService.shared.refine(text: textToRefine)
    }
    
    func transcribe(samples: [Float]) {
        // Don't accept new transcription requests after stop
        guard isModelReady, !isStopped, let asrManager = asrManager else { return }
        
        // If a transcription is already in-flight, queue this one
        // (only the latest request is kept — older ones are dropped)
        if isTranscribing {
            pendingSamples = samples
            return
        }
        
        performTranscription(samples: samples, manager: asrManager)
    }
    
    private func performTranscription(samples: [Float], manager: AsrManager) {
        isTranscribing = true
        
        Task {
            do {
                let result = try await manager.transcribe(samples, source: .system)
                
                // Only update transcript if we haven't been stopped
                if !self.isStopped {
                    await MainActor.run {
                        if !result.text.isEmpty {
                            self.transcript = result.text
                            print("[Hermes.ASR] transcript updated='\(result.text.prefix(50))' length=\(result.text.count)")
                        }
                    }
                } else {
                    print("[Hermes.ASR] Discarding late transcription result (session stopped)")
                }
            } catch {
                print("Transcription error: \(error)")
            }
            
            // Check if new samples arrived while we were transcribing
            self.isTranscribing = false
            if !self.isStopped, let pending = self.pendingSamples {
                self.pendingSamples = nil
                self.performTranscription(samples: pending, manager: manager)
            }
        }
    }
}
