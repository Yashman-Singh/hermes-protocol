import Foundation
import AVFoundation
import Combine
import SwiftUI

class AudioService: ObservableObject {
    static let shared = AudioService()
    
    private let engine = AVAudioEngine()
    private var isRecording = false
    
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
    
    @Published var isRecordingState = false
    @Published var hasMicrophonePermission = false
    
    /// True while chunks are being transcribed/processed. Keeps the orb visible.
    @Published var isProcessingPipeline = false
    
    // MARK: - Chunk Pipeline
    
    /// Seconds of audio per chunk (Raw/Editor streaming modes).
    private let chunkDuration: TimeInterval = 8.0
    
    /// Audio samples for the current chunk being recorded.
    private var accumulatedSamples: [Float] = []
    
    /// Timer that fires every `chunkDuration` to freeze and queue the current chunk.
    private var chunkTimer: Timer?
    
    /// Queue of frozen audio chunks waiting to be processed.
    private var chunkQueue: [[Float]] = []
    
    /// Whether the pipeline is currently processing a chunk.
    private var isProcessingChunk = false
    
    /// Index of the next chunk (for ordered injection).
    private var nextChunkIndex = 0
    
    /// Incomplete sentence tail from the previous chunk, carried forward.
    private var carryForwardText: String = ""
    
    /// Whether recording has stopped (used to detect when pipeline should flush carry).
    private var hasRecordingStopped = false
    
    private let fluidAudio = FluidAudio.shared
    
    // Writer mode: accumulate everything, process at the end.
    // Max buffer: 5 minutes at 16kHz = 4,800,000 samples (~19 MB).
    private let writerMaxSampleCount = 4_800_000
    
    // MARK: - Permissions
    
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
    
    // MARK: - Recording
    
    func startRecording() throws {
        guard !isRecording else { return }
        
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
        chunkQueue.removeAll()
        isProcessingChunk = false
        nextChunkIndex = 0
        carryForwardText = ""
        hasRecordingStopped = false
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "AudioService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid audio input format — is a microphone connected?"])
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "AudioService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
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
        
        // Prepare services
        LLMService.shared.prepareForSession()
        InjectorService.shared.beginSession()
        fluidAudio.prepareForNewSession()
        
        Task {
            await fluidAudio.startSession()
        }
        
        // Start chunk timer for Raw/Editor modes (not Writer)
        let level = RefinementLevel(rawValue: LLMService.shared.intensity) ?? .editor
        if level != .writer {
            startChunkTimer()
        }
        
        DispatchQueue.main.async {
            self.isRecordingState = true
        }
        print("[Hermes.Audio] Recording started (mode: \(level))")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        print("[Hermes.Audio] stopRecording()")
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        stopChunkTimer()
        fluidAudio.stopSession()
        
        let level = RefinementLevel(rawValue: LLMService.shared.intensity) ?? .editor
        
        if level == .writer {
            // Writer mode: send the full accumulated audio as one chunk
            if !accumulatedSamples.isEmpty {
                print("[Hermes.Audio] Writer mode — queuing full recording (\(accumulatedSamples.count) samples)")
                chunkQueue.append(accumulatedSamples)
                accumulatedSamples.removeAll()
                processNextChunk(isFinal: true)
            } else {
                LLMService.shared.markRecordingStopped()
            }
        } else {
            // Raw/Editor: flush remaining audio as the final chunk
            if accumulatedSamples.count > 8000 { // At least 0.5s of audio
                print("[Hermes.Audio] Flushing final chunk (\(accumulatedSamples.count) samples)")
                chunkQueue.append(accumulatedSamples)
                accumulatedSamples.removeAll()
                processNextChunk(isFinal: true)
            } else {
                // No remaining audio — but there might be carry text
                // or a chunk still processing
                hasRecordingStopped = true
                flushCarryIfDone()
            }
        }
        
        DispatchQueue.main.async {
            self.isRecordingState = false
        }
        print("[Hermes.Audio] stopRecording() complete")
    }
    
    // MARK: - Chunk Timer
    
    private func startChunkTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.chunkTimer = Timer.scheduledTimer(withTimeInterval: self.chunkDuration, repeats: true) { [weak self] _ in
                self?.freezeCurrentChunk()
            }
            print("[Hermes.Audio] Chunk timer started (\(self.chunkDuration)s intervals)")
        }
    }
    
    private func stopChunkTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.chunkTimer?.invalidate()
            self?.chunkTimer = nil
        }
    }
    
    /// Called by the chunk timer: freeze current audio, queue it, start fresh.
    private func freezeCurrentChunk() {
        guard isRecording else { return }
        guard accumulatedSamples.count > 8000 else { return } // At least 0.5s
        
        let chunk = accumulatedSamples
        accumulatedSamples.removeAll()
        
        print("[Hermes.Audio] ❄️ Froze chunk #\(nextChunkIndex + chunkQueue.count) (\(chunk.count) samples, \(String(format: "%.1f", Double(chunk.count) / 16000))s)")
        
        chunkQueue.append(chunk)
        processNextChunk(isFinal: false)
    }
    
    // MARK: - Chunk Processing Pipeline
    
    /// Process the next chunk in the queue: Transcribe → LLM → Inject.
    private func processNextChunk(isFinal: Bool) {
        guard !isProcessingChunk else { return } // One at a time
        guard !chunkQueue.isEmpty else {
            if isFinal {
                LLMService.shared.markRecordingStopped()
            }
            return
        }
        
        isProcessingChunk = true
        let samples = chunkQueue.removeFirst()
        let chunkIndex = nextChunkIndex
        nextChunkIndex += 1
        
        DispatchQueue.main.async {
            self.isProcessingPipeline = true
        }
        
        print("[Hermes.Audio] 🔄 Processing chunk #\(chunkIndex)")
        
        Task {
            // 1. Transcribe the audio chunk
            let rawTranscript = await fluidAudio.transcribeChunk(samples: samples)
            
            guard !rawTranscript.isEmpty else {
                print("[Hermes.Audio] Chunk #\(chunkIndex) produced empty transcript — skipping")
                await MainActor.run {
                    self.isProcessingChunk = false
                    self.processNextChunk(isFinal: isFinal && self.chunkQueue.isEmpty)
                }
                return
            }
            
            // 2. Prepend any carried-over text from the previous chunk
            let fullText = await MainActor.run { () -> String in
                let combined = self.carryForwardText.isEmpty
                    ? rawTranscript
                    : self.carryForwardText + " " + rawTranscript
                return combined
            }
            
            let isLastChunk = isFinal && self.chunkQueue.isEmpty
            
            // 3. Split at last sentence boundary
            //    Only inject complete sentences; carry the tail forward.
            //    On the final chunk, inject everything.
            let (toInject, toCarry) = self.splitAtSentenceBoundary(
                text: fullText,
                forceAll: isLastChunk
            )
            
            await MainActor.run {
                self.carryForwardText = toCarry
            }
            
            if !toInject.isEmpty {
                print("[Hermes.Audio] Chunk #\(chunkIndex) injecting: '\(toInject.prefix(60))' carry: '\(toCarry.prefix(40))'")
                await MainActor.run {
                    LLMService.shared.refineSegment(text: toInject, isFinal: isLastChunk && toCarry.isEmpty)
                }
            } else {
                print("[Hermes.Audio] Chunk #\(chunkIndex) no complete sentence yet — carrying forward \(toCarry.count) chars")
                if isLastChunk && !toCarry.isEmpty {
                    // Final chunk but no sentence boundary — flush carry
                    await MainActor.run {
                        self.carryForwardText = ""
                        LLMService.shared.refineSegment(text: toCarry, isFinal: true)
                    }
                } else if isLastChunk {
                    await MainActor.run {
                        LLMService.shared.markRecordingStopped()
                    }
                }
            }
            
            // 4. Continue with next chunk
            await MainActor.run {
                self.isProcessingChunk = false
                if !self.chunkQueue.isEmpty {
                    self.processNextChunk(isFinal: isFinal)
                } else {
                    self.flushCarryIfDone()
                }
            }
        }
    }
    
    /// Flush any leftover carry text when the pipeline is idle and recording has stopped.
    private func flushCarryIfDone() {
        guard hasRecordingStopped else { return }
        guard !isProcessingChunk && chunkQueue.isEmpty else { return }
        
        if !carryForwardText.isEmpty {
            let carry = carryForwardText
            carryForwardText = ""
            print("[Hermes.Audio] Flushing carried text on stop: '\(carry.prefix(60))'")
            LLMService.shared.refineSegment(text: carry, isFinal: true)
        } else {
            LLMService.shared.markRecordingStopped()
        }
        
        isProcessingPipeline = false
    }
    
    // MARK: - Sentence Boundary Detection
    
    /// Split text at the last sentence boundary.
    /// Returns (complete sentences to inject, incomplete tail to carry forward).
    /// If `forceAll` is true (final chunk), returns everything as toInject.
    private func splitAtSentenceBoundary(text: String, forceAll: Bool) -> (toInject: String, toCarry: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if forceAll || trimmed.isEmpty {
            return (trimmed, "")
        }
        
        // Safety valve: if carry has grown too long (>300 chars), flush everything
        if trimmed.count > 300 {
            print("[Hermes.Audio] Carry exceeded 300 chars — forcing injection")
            return (trimmed, "")
        }
        
        // Find the last sentence-ending punctuation followed by a space or end
        let sentenceEnders: [Character] = [".", "?", "!"]
        var lastBoundary: String.Index? = nil
        
        for i in trimmed.indices {
            if sentenceEnders.contains(trimmed[i]) {
                let nextIdx = trimmed.index(after: i)
                // It's a sentence boundary if at the end OR followed by a space
                if nextIdx == trimmed.endIndex || trimmed[nextIdx] == " " {
                    lastBoundary = i
                }
            }
        }
        
        guard let boundary = lastBoundary else {
            // No sentence boundary found — carry everything
            return ("", trimmed)
        }
        
        let splitIdx = trimmed.index(after: boundary)
        let toInject = String(trimmed[trimmed.startIndex..<splitIdx])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let toCarry = String(trimmed[splitIdx...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (toInject, toCarry)
    }
    
    // MARK: - Audio Processing
    
    private func processAudio(buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let ptr = floatChannelData[0]
        let newSamples = Array(UnsafeBufferPointer(start: ptr, count: frameLength))
        
        accumulatedSamples.append(contentsOf: newSamples)
        
        // For Writer mode: cap at 5 minutes
        let level = RefinementLevel(rawValue: LLMService.shared.intensity) ?? .editor
        if level == .writer && accumulatedSamples.count > writerMaxSampleCount {
            accumulatedSamples = Array(accumulatedSamples.suffix(writerMaxSampleCount))
        }
        
        // Live preview: update transcript with current buffer
        // (only for Raw/Editor — Writer shows the full transcript at the end)
        if level != .writer && accumulatedSamples.count > 16000 && isRecording {
            fluidAudio.transcribeLive(samples: accumulatedSamples)
        }
    }
}
