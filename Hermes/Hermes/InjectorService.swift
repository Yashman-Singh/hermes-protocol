import Foundation
import ApplicationServices
import Cocoa

class InjectorService {
    static let shared = InjectorService()
    
    private init() {}
    
    func inject(text: String) {
        guard !text.isEmpty else { return }
        
        // Hide the Hermes window to return focus to the previous active app
        NSApplication.shared.hide(nil)
        
        // Wait for focus to switch back and start attempts
        // Increased delay to 0.5s to ensure window switching is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.attemptInjection(text: text, retries: 3)
        }
    }
    
    enum InjectionResult {
        case success
        case failure // Retryable (e.g. focus issue)
        case clipboardRequired // Non-retryable (known blocklist)
    }

    private func attemptInjection(text: String, retries: Int) {
        let result = self.injectViaAccessibility(text: text)
        
        switch result {
        case .success:
            print("Injected via Accessibility")
            
        case .clipboardRequired:
            print("App requires Clipboard. Skipping retries.")
            self.injectViaClipboard(text: text)
            print("Injected via Clipboard")
            
        case .failure:
            // If failed, check if we should retry
            if retries > 0 {
                print("Accessibility failed/refused, retrying in 0.3s... (\(retries) retries left)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.attemptInjection(text: text, retries: retries - 1)
                }
            } else {
                // 2. Fallback to Clipboard
                print("Accessibility exhausted. Falling back to Clipboard.")
                self.injectViaClipboard(text: text)
                print("Injected via Clipboard")
            }
        }
    }
    
    func canUseAccessibilityForCurrentApp() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        let appName = frontApp.localizedName ?? "Unknown"
        let clipboardOnlyApps = ["Antigravity", "Code", "Cursor", "Slack", "Discord", "Electron"]
        
        return !clipboardOnlyApps.contains(where: { appName.contains($0) })
    }

    private func injectViaAccessibility(text: String) -> InjectionResult {
        // Get the frontmost application (more reliable than SystemWide focused element)
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("Could not determine frontmost application.")
            return .failure
        }
        
        // Prevent injecting into Hermes itself
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            print("Hermes is still frontmost. Retrying...")
            return .failure
        }
        
        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "Unknown"
        
        if !canUseAccessibilityForCurrentApp() {
            print("'\(appName)' is in the clipboard-only list. Skipping Accessibility.")
            return .clipboardRequired
        }
        
        // Check for Electron App (needs manual accessibility enabled)
        ensureElectronAccessibility(pid: pid)
        
        // Create Accessibility Application Element
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the Focused Element within that App
        var focusedElement: AnyObject?
        let error = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard error == .success, let element = focusedElement as! AXUIElement? else {
            print("Could not get focused element in \(appName). Error: \(error.rawValue)")
            return .failure
        }
        
        // Try to insert text at cursor position (works for rich text editors like Notes)
        let valueError = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        
        if valueError == .success {
            return .success
        }
        
        print("Accessibility SetValue failed with error: \(valueError.rawValue)")
        return .failure
    }
    
    private func ensureElectronAccessibility(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        // Set AXManualAccessibility = true (needed for VS Code, Obsidian, Slack, etc.)
        let _ = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
    }
    
    private func injectViaClipboard(text: String) {
        // Backup current clipboard
        let pasteboard = NSPasteboard.general
        let _ = pasteboard.string(forType: .string) // Read to clear potential lazy writes? Or just ignore.
        
        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Restore clipboard (optional, delayed)
        // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        //    if let old = oldString {
        //        pasteboard.clearContents()
        //        pasteboard.setString(old, forType: .string)
        //    }
        // }
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let vKeyCode: CGKeyCode = 9 // 'v' key
        
        // Cmd down
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        
        // V down
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        vDown?.flags = .maskCommand
        
        // V up
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        vUp?.flags = .maskCommand
        
        // Cmd up
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        // Post events
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
