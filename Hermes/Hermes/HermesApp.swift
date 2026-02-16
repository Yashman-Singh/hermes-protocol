import SwiftUI
import Combine

@main
struct HermesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup Menu Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Hermes")
            button.action = #selector(menuBarClicked)
        }
        
        // 2. Setup Overlay Window
        WindowManager.shared.setup()
        
        // 3. Initialize HotKey Manager
        _ = HotKeyManager.shared
        
        // 4. Bind Recording State to Window Visibility
        AudioService.shared.$isRecordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                // Update Menu Bar Icon
                if let button = self?.statusItem?.button {
                    button.image = NSImage(systemSymbolName: isRecording ? "record.circle.fill" : "waveform.circle", accessibilityDescription: "Hermes")
                }
                
                // Show/Hide Overlay
                if isRecording {
                    WindowManager.shared.show()
                } else {
                    WindowManager.shared.hide()
                    // Re-hide app to ensure focus returns to previous app
                    NSApplication.shared.hide(nil)
                }
            }
            .store(in: &cancellables)
    }
    
    @objc func menuBarClicked() {
        // Option to quit or show settings could go here
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Hermes", action: #selector(terminate), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // specific hack for simple click vs menu
    }
    
    @objc func terminate() {
        NSApplication.shared.terminate(nil)
    }
}
