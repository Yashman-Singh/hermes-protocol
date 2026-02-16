import Foundation
import Combine
import HotKey
import AppKit

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    // Default: Option + S (S for Speech/Start)
    private let hotKey = HotKey(key: .s, modifiers: [.option])
    
    @Published var isRecording = false
    
    private init() {
        // Handle Key Down
        hotKey.keyDownHandler = { [weak self] in
            self?.toggleRecording()
        }
    }
    
    func toggleRecording() {
        Task { @MainActor in
            if AudioService.shared.isRecordingState {
                AudioService.shared.stopRecording()
                self.isRecording = false
            } else {
                do {
                    try AudioService.shared.startRecording()
                    self.isRecording = true
                } catch {
                    print("Failed to start recording via HotKey: \(error)")
                }
            }
        }
    }
}
