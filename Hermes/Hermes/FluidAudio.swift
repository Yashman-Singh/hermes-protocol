import Foundation
import AVFoundation
import Combine
import FluidAudio

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
            // Download and load the v3 Parakeet model (approx 100-300MB)
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
    
    func requestPermission() {
        // FluidAudio (local) doesn't strictly need SFSpeechRecognizer permission, 
        // but it's good practice if we fall back or use mic. 
        // Since AudioService handles Mic permission, we are good.
        // We can leave this empty or remove it.
    }
    
    func start() async throws {
        // Reset state if needed
        await MainActor.run {
            self.transcript = ""
        }
    }
    
    func stop() {
        // Trigger injection of the final transcript with a trailing space
        let textToInject = self.transcript + " "
        Task { @MainActor in
            InjectorService.shared.inject(text: textToInject)
        }
    }
    
    func transcribe(samples: [Float]) {
        guard isModelReady, let asrManager = asrManager else { return }
        
        Task {
            do {
                // Perform transcription on the accumulated samples
                let result = try await asrManager.transcribe(samples, source: .system)
                
                await MainActor.run {
                    if !result.text.isEmpty {
                        self.transcript = result.text
                    }
                }
            } catch {
                print("Transcription error: \(error)")
            }
        }
    }
}
