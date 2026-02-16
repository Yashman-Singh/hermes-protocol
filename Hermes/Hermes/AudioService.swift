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
    
    func startRecording() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
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
        
        Task {
            try? await fluidAudio.start()
        }
        
        DispatchQueue.main.async {
            self.isRecordingState = true
        }
    }
    
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        fluidAudio.stop()
        DispatchQueue.main.async {
            self.isRecordingState = false
            self.accumulatedSamples.removeAll()
        }
    }
    
    private let fluidAudio = FluidAudio.shared
    private var accumulatedSamples: [Float] = []
    
    private func processAudio(buffer: AVAudioPCMBuffer) {
        // 1. Extract samples from buffer
        guard let floatChannelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let ptr = floatChannelData[0] // Mono
        let newSamples = Array(UnsafeBufferPointer(start: ptr, count: frameLength))
        
        // 2. Accumulate
        accumulatedSamples.append(contentsOf: newSamples)
        
        // 3. Check threshold (1 second = 16000 samples)
        // We continue appending to provide context, so we re-transcribe the growing buffer.
        // This simulates "partial results".
        if accumulatedSamples.count > 16000 {
            fluidAudio.transcribe(samples: accumulatedSamples)
        }
    }
    
    // Helper to request permission
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("Audio access granted")
            } else {
                print("Audio access denied")
            }
        }
    }
}
