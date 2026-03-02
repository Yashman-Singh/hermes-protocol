import Foundation
import AVFoundation
import Combine

class AudioService: ObservableObject {
    static let shared = AudioService()
    
    private let engine = AVAudioEngine()
    private var isRecording = false
    
    // Explicitly define the target format: 16kHz, Float32, Mono
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
    
    @Published var isRecordingState = false
    @Published var hasMicrophonePermission = false
    
    // Maximum buffer: 30 seconds at 16kHz = 480,000 samples
    private let maxSampleCount = 480_000
    
    /// Must be called on app launch to trigger the permission dialog.
    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = true
            }
            completion?(true)
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasMicrophonePermission = granted
                }
                if granted {
                    print("Microphone access granted")
                } else {
                    print("Microphone access denied")
                }
                completion?(granted)
            }
            
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = false
            }
            print("Microphone access denied/restricted. Open System Settings → Privacy & Security → Microphone.")
            completion?(false)
            
        @unknown default:
            completion?(false)
        }
    }
    
    func startRecording() throws {
        guard !isRecording else { return }
        
        // Guard: ensure we have mic permission before touching the audio engine
        guard hasMicrophonePermission else {
            print("Cannot start recording: no microphone permission.")
            requestPermission { [weak self] granted in
                if granted {
                    try? self?.startRecording()
                }
            }
            return
        }
        
        accumulatedSamples.removeAll()
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Validate input format (some machines may return 0 sample rate if no mic)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "AudioService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid audio input format — is a microphone connected?"])
        }
        
        // Ensure we accept the input format but convert to our target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "AudioService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Calculate format conversion ratio
            let inputFrameCount = buffer.frameLength
            let conversionRatio = 16000 / inputFormat.sampleRate
            let targetFrameCount = AVAudioFrameCount(Double(inputFrameCount) * conversionRatio)
            
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: targetFrameCount) else {
                print("Failed to create output buffer")
                return
            }
            
            var error: NSError? = nil
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            
            if status != .error {
                self.processAudio(buffer: outputBuffer)
            } else {
                print("Conversion error: \(String(describing: error))")
            }
        }
        
        try engine.start()
        isRecording = true
        
        // Reset FluidAudio state synchronously so it's ready before
        // the first audio callback fires. The async Task is only for
        // the MainActor transcript clear, which is cosmetic.
        fluidAudio.prepareForNewSession()
        Task {
            try? await fluidAudio.start()
        }
        
        DispatchQueue.main.async {
            self.isRecordingState = true
        }
        print("[Hermes.Audio] Recording started")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        print("[Hermes.Audio] stopRecording() — removing tap, stopping engine")
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        // Clear samples synchronously BEFORE calling fluidAudio.stop()
        accumulatedSamples.removeAll()
        
        fluidAudio.stop()
        
        DispatchQueue.main.async {
            self.isRecordingState = false
        }
        print("[Hermes.Audio] stopRecording() complete")
    }
    
    private let fluidAudio = FluidAudio.shared
    private var accumulatedSamples: [Float] = []
    
    private func processAudio(buffer: AVAudioPCMBuffer) {
        // 1. Extract samples from buffer
        guard let floatChannelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let ptr = floatChannelData[0] // Mono
        let newSamples = Array(UnsafeBufferPointer(start: ptr, count: frameLength))
        
        // 2. Accumulate (capped to prevent unbounded growth)
        accumulatedSamples.append(contentsOf: newSamples)
        if accumulatedSamples.count > maxSampleCount {
            // Keep only the most recent samples (sliding window)
            accumulatedSamples = Array(accumulatedSamples.suffix(maxSampleCount))
        }
        
        // 3. Dispatch transcription once we have at least 1 second of audio
        // FluidAudio handles deduplication — if a transcription is in-flight,
        // it queues the latest samples and processes them when ready.
        // Guard: don't dispatch if recording has stopped
        if accumulatedSamples.count > 16000 && isRecording {
            fluidAudio.transcribe(samples: accumulatedSamples)
        }
    }
}
