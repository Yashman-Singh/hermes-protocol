import SwiftUI
import Combine

@main
struct HermesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No visible windows — the app lives in the menu bar
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var cancellables = Set<AnyCancellable>()
    var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup Menu Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Hermes")
            button.action = #selector(togglePopover)
        }
        
        // 2. Setup Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient // Dismiss when clicking outside
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: SettingsPopoverView())
        self.popover = popover
        
        // 3. Setup Overlay Window
        WindowManager.shared.setup()
        
        // 4. Initialize HotKey Manager
        _ = HotKeyManager.shared
        
        // 5. Bind Recording and Refining State to Window Visibility
        Publishers.CombineLatest(AudioService.shared.$isRecordingState, LLMService.shared.$isRefining)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isRefining in
                // Update Menu Bar Icon
                if let button = self?.statusItem?.button {
                    button.image = NSImage(systemSymbolName: isRecording ? "record.circle.fill" : (isRefining ? "brain" : "waveform.circle"), accessibilityDescription: "Hermes")
                }
                
                // Show/Hide Overlay
                if isRecording || isRefining {
                    WindowManager.shared.show()
                } else {
                    WindowManager.shared.hide()
                    // Re-hide app to ensure focus returns to previous app
                    NSApplication.shared.hide(nil)
                }
            }
            .store(in: &cancellables)
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make the popover window visible on all Spaces (including full-screen apps)
            if let popoverWindow = popover?.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
                popoverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
        }
    }
}
