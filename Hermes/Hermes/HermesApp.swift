import SwiftUI
import Combine
import UserNotifications

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
        // 0. Kill any zombie Hermes processes from previous runs
        if let myBundle = Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: myBundle)
            where app != NSRunningApplication.current {
                app.terminate()
                print("[Hermes] Terminated zombie process: pid=\(app.processIdentifier)")
            }
        }
        
        // 1. Setup Menu Bar Item (starts with loading icon)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Hermes (Loading...)")
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
        
        // 5. Request Microphone Permission (triggers dialog on first launch)
        AudioService.shared.requestPermission()
        
        // 6. Prompt for Accessibility permission up front (required for text injection).
        InjectorService.shared.requestAccessibilityPermissionIfNeeded()
        
        // 7. Watch for FluidAudio model readiness
        FluidAudio.shared.$isModelReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                guard isReady else { return }
                // Switch menu bar icon from loading to ready
                if let button = self?.statusItem?.button {
                    button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Hermes")
                }
                // Show a macOS notification
                self?.showReadyNotification()
            }
            .store(in: &cancellables)
        
        // 8. Bind Recording and Refining State to Window Visibility
        Publishers.CombineLatest(AudioService.shared.$isRecordingState, LLMService.shared.$isRefining)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isRefining in
                guard FluidAudio.shared.isModelReady else { return }
                // Update Menu Bar Icon
                if let button = self?.statusItem?.button {
                    button.image = NSImage(systemSymbolName: isRecording ? "record.circle.fill" : (isRefining ? "brain" : "waveform.circle"), accessibilityDescription: "Hermes")
                }
                
                // Show/Hide Overlay
                if isRecording || isRefining {
                    WindowManager.shared.show()
                } else {
                    WindowManager.shared.hide()
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
            if let popoverWindow = popover?.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
                popoverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
        }
    }
    
    private func showReadyNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Hermes is ready"
            content.body = "Press ⌥S to start dictating."
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: "hermes-ready", content: content, trigger: nil)
            center.add(request)
        }
    }
}
