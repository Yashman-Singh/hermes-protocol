import Foundation
import ApplicationServices
import Cocoa

class InjectorService {
    static let shared = InjectorService()
    
    private init() {}
    
    private enum InjectionMode {
        case accessibility
        case clipboard
    }
    
    private struct FocusContext: Hashable {
        let bundleIdentifier: String
        let role: String
        let subrole: String?
        let isWebContext: Bool
        
        var cacheKey: String {
            "\(bundleIdentifier)|\(role)|\(subrole ?? "-")|web:\(isWebContext)"
        }
    }
    
    private struct FocusTarget {
        let frontApp: NSRunningApplication
        let appName: String
        let element: AXUIElement
        let context: FocusContext
    }
    
    private let policyLock = NSLock()
    private var preferredInjectionByContext: [String: InjectionMode] = [:]
    private var clipboardPreferredBundles: Set<String> = []
    private let browserLikeRoles: Set<String> = ["AXWebArea", "AXBrowser"]
    private let browserBundleTokens = ["browser", "chrome", "safari", "firefox", "brave", "edge", "opera", "vivaldi"]
    private let immediateClipboardFocusErrorCodes: Set<Int32> = [-25212]
    private let debugLoggingEnabled = true
    
    /// Clipboard snapshot saved at session start — restored when all segments are done.
    private var savedClipboard: [[NSPasteboard.PasteboardType: Data]]?
    
    // MARK: - Streaming Segment Injection
    
    /// Snapshot the clipboard at the start of a recording session.
    func beginSession() {
        savedClipboard = snapshotPasteboardItems(NSPasteboard.general)
        debugLog("Session started — clipboard saved")
    }
    
    /// Lightweight inject for streaming segments during recording.
    /// Target app already has focus — just clipboard + Cmd+V.
    /// No app hide, no delays, no clipboard restore.
    func injectSegment(text: String) {
        guard !text.isEmpty else { return }
        debugLog("Segment inject: '\(text.prefix(60))' length=\(text.count)")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simulatePaste()
    }
    
    /// Called after all segments are injected. Restores the original clipboard.
    func finalizeSession() {
        debugLog("Session finalized — restoring clipboard")
        if let saved = savedClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.restorePasteboardItems(saved, to: NSPasteboard.general)
                self?.savedClipboard = nil
            }
        }
    }
    
    @discardableResult
    func hasAccessibilityPermission(promptIfNeeded: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func requestAccessibilityPermissionIfNeeded() {
        guard !hasAccessibilityPermission(promptIfNeeded: false) else { return }
        _ = hasAccessibilityPermission(promptIfNeeded: true)
        print("Accessibility permission required. Open System Settings → Privacy & Security → Accessibility and enable Hermes.")
    }
    
    func inject(text: String) {
        guard !text.isEmpty else { return }
        debugLog("Inject requested. textLength=\(text.count)")
        
        // If we don't have accessibility permission, fall back to clipboard
        // without re-prompting. The prompt is shown once on launch.
        guard hasAccessibilityPermission(promptIfNeeded: false) else {
            debugLog("No accessibility permission — falling back to clipboard")
            injectViaClipboard(text: text)
            return
        }
        
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
        case clipboardRequired // Non-retryable (context prefers clipboard)
    }

    private func attemptInjection(text: String, retries: Int) {
        debugLog("Attempt injection. retriesRemaining=\(retries)")
        
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontBundle = frontApp?.bundleIdentifier
        if let frontBundle, isClipboardPreferredBundle(frontBundle) {
            debugLog("Bundle cached for clipboard. bundle=\(frontBundle)")
            injectViaClipboard(text: text)
            print("Injected via Clipboard")
            return
        }
        
        let resolution = resolveFocusedTarget()
        guard let target = resolution.target else {
            if let bundle = frontBundle, let focusError = resolution.error,
               shouldImmediatelyFallbackToClipboard(focusErrorCode: focusError.rawValue) {
                rememberClipboardPreferredBundle(bundle)
                debugLog("Focus error \(focusError.rawValue) triggers immediate clipboard mode. bundle=\(bundle)")
                injectViaClipboard(text: text)
                print("Injected via Clipboard")
                return
            }
            
            if retries > 0 {
                print("Could not resolve focused element, retrying in 0.3s... (\(retries) retries left)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.attemptInjection(text: text, retries: retries - 1)
                }
            } else {
                if let bundle = frontBundle {
                    rememberClipboardPreferredBundle(bundle)
                }
                print("Unable to resolve focused element. Falling back to Clipboard.")
                injectViaClipboard(text: text)
                print("Injected via Clipboard")
            }
            return
        }
        
        // Prevent injecting into Hermes itself
        if target.frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            if retries > 0 {
                print("Hermes is still frontmost. Retrying... (\(retries) retries left)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.attemptInjection(text: text, retries: retries - 1)
                }
            } else {
                injectViaClipboard(text: text)
                print("Injected via Clipboard")
            }
            return
        }
        
        // Check for Electron App (needs manual accessibility enabled)
        ensureElectronAccessibility(pid: target.frontApp.processIdentifier)
        
        let mode = preferredInjectionMode(for: target.context)
        debugLog("Resolved context app=\(target.appName) bundle=\(target.context.bundleIdentifier) role=\(target.context.role) subrole=\(target.context.subrole ?? "-") mode=\(modeName(mode))")
        let result: InjectionResult
        
        switch mode {
        case .clipboard:
            result = .clipboardRequired
        case .accessibility:
            result = injectViaAccessibility(element: target.element, appName: target.appName, text: text)
        }
        
        switch result {
        case .success:
            rememberPreferredMode(.accessibility, for: target.context)
            print("Injected via Accessibility")
            debugLog("Result=success via accessibility")
            
        case .clipboardRequired:
            rememberPreferredMode(.clipboard, for: target.context)
            print("Context prefers Clipboard. Skipping retries.")
            self.injectViaClipboard(text: text)
            print("Injected via Clipboard")
            debugLog("Result=clipboardRequired; used clipboard")
            
        case .failure:
            // If failed, check if we should retry
            if retries > 0 {
                print("Accessibility failed/refused, retrying in 0.3s... (\(retries) retries left)")
                debugLog("Result=failure via accessibility; scheduling retry")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.attemptInjection(text: text, retries: retries - 1)
                }
            } else {
                // Last resort: fallback to clipboard and remember this context.
                print("Accessibility exhausted. Falling back to Clipboard.")
                rememberPreferredMode(.clipboard, for: target.context)
                self.injectViaClipboard(text: text)
                print("Injected via Clipboard")
                debugLog("Result=failure exhausted; fell back to clipboard and cached context")
            }
        }
    }
    
    func canUseAccessibilityForCurrentApp() -> Bool {
        guard hasAccessibilityPermission(promptIfNeeded: false) else {
            return false
        }
        
        let resolution = resolveFocusedTarget()
        guard let target = resolution.target else {
            return false
        }
        
        return preferredInjectionMode(for: target.context) == .accessibility
    }

    private func injectViaAccessibility(element: AXUIElement, appName: String, text: String) -> InjectionResult {
        // Insert text at cursor via kAXSelectedTextAttribute (works in most native text editors)
        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            debugLog("AX selectedText succeeded for app=\(appName)")
            return .success
        }
        
        print("Accessibility text insertion failed for \(appName).")
        debugLog("AX insertion failed for app=\(appName)")
        return .failure
    }
    
    private func resolveFocusedTarget() -> (target: FocusTarget?, error: AXError?) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil)
        }
        
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleIdentifier = frontApp.bundleIdentifier ?? "unknown.bundle"
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        var focusedElement: AnyObject?
        let focusError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusError == .success, let rawElement = focusedElement else {
            print("Could not get focused element in \(appName). Error: \(focusError.rawValue)")
            return (nil, focusError)
        }
        
        let element = rawElement as! AXUIElement
        let role = copyStringAttribute(from: element, attribute: kAXRoleAttribute as CFString) ?? "UnknownRole"
        let subrole = copyStringAttribute(from: element, attribute: kAXSubroleAttribute as CFString)
        let isWebContext = role == "AXWebArea" || hasAncestorRole("AXWebArea", for: element)
        let context = FocusContext(
            bundleIdentifier: bundleIdentifier,
            role: role,
            subrole: subrole,
            isWebContext: isWebContext
        )
        
        return (FocusTarget(frontApp: frontApp, appName: appName, element: element, context: context), nil)
    }
    
    private func preferredInjectionMode(for context: FocusContext) -> InjectionMode {
        policyLock.lock()
        if let cached = preferredInjectionByContext[context.cacheKey] {
            policyLock.unlock()
            debugLog("Using cached mode=\(modeName(cached)) context=\(context.cacheKey)")
            return cached
        }
        policyLock.unlock()
        
        if context.isWebContext {
            debugLog("Defaulting to clipboard for web-context role chain. context=\(context.cacheKey)")
            return .clipboard
        }
        
        let lowerBundle = context.bundleIdentifier.lowercased()
        if browserBundleTokens.contains(where: { lowerBundle.contains($0) }) {
            debugLog("Defaulting to clipboard for browser-like bundle token. context=\(context.cacheKey)")
            return .clipboard
        }
        
        if browserLikeRoles.contains(context.role) {
            debugLog("Defaulting to clipboard for browser-like role=\(context.role) context=\(context.cacheKey)")
            return .clipboard
        }
        
        debugLog("Defaulting to accessibility context=\(context.cacheKey)")
        return .accessibility
    }
    
    private func rememberPreferredMode(_ mode: InjectionMode, for context: FocusContext) {
        policyLock.lock()
        preferredInjectionByContext[context.cacheKey] = mode
        policyLock.unlock()
        debugLog("Cached mode=\(modeName(mode)) context=\(context.cacheKey)")
    }
    
    private func isClipboardPreferredBundle(_ bundleIdentifier: String) -> Bool {
        policyLock.lock()
        let isPreferred = clipboardPreferredBundles.contains(bundleIdentifier)
        policyLock.unlock()
        return isPreferred
    }
    
    private func rememberClipboardPreferredBundle(_ bundleIdentifier: String) {
        policyLock.lock()
        clipboardPreferredBundles.insert(bundleIdentifier)
        policyLock.unlock()
        debugLog("Cached clipboard-preferred bundle=\(bundleIdentifier)")
    }
    
    private func shouldImmediatelyFallbackToClipboard(focusErrorCode: Int32) -> Bool {
        immediateClipboardFocusErrorCodes.contains(focusErrorCode)
    }
    
    private func copyStringAttribute(from element: AXUIElement, attribute: CFString) -> String? {
        var rawValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        guard error == .success, let value = rawValue as? String else {
            return nil
        }
        return value
    }
    
    private func hasAncestorRole(_ role: String, for element: AXUIElement, maxDepth: Int = 8) -> Bool {
        var current: AXUIElement = element
        var remainingDepth = maxDepth
        
        while remainingDepth > 0 {
            if copyStringAttribute(from: current, attribute: kAXRoleAttribute as CFString) == role {
                return true
            }
            
            var parentValue: AnyObject?
            let parentError = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard parentError == .success, let rawParent = parentValue else {
                return false
            }
            
            current = rawParent as! AXUIElement
            remainingDepth -= 1
        }
        
        return false
    }
    
    private func ensureElectronAccessibility(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        // Set AXManualAccessibility = true (needed for VS Code, Obsidian, Slack, etc.)
        let _ = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
    }
    
    private func injectViaClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        let previousItems = snapshotPasteboardItems(pasteboard)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Restore the user's previous clipboard after a generous delay.
        // 1.5s ensures even slow web apps (Google Docs) have finished
        // reading the clipboard before we swap it back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.restorePasteboardItems(previousItems, to: pasteboard)
            self?.debugLog("Clipboard restored to previous contents")
        }
    }
    
    private func copyToClipboardForManualPaste(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print("Accessibility permission not granted. Copied text to clipboard for manual paste.")
    }
    


    
    private func snapshotPasteboardItems(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        
        return items.map { item in
            var storedData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    storedData[type] = data
                }
            }
            return storedData
        }
    }
    
    private func restorePasteboardItems(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        guard !snapshot.isEmpty else { return }
        
        let restoredItems: [NSPasteboardItem] = snapshot.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        
        pasteboard.clearContents()
        pasteboard.writeObjects(restoredItems)
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
        debugLog("Simulated Cmd+V paste")
    }
    
    private func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        print("[Hermes.Injector] \(message)")
    }
    
    private func modeName(_ mode: InjectionMode) -> String {
        switch mode {
        case .accessibility:
            return "accessibility"
        case .clipboard:
            return "clipboard"
        }
    }
}
