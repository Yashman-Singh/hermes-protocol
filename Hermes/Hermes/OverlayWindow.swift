import Cocoa
import SwiftUI
import Combine

class OverlayWindow: NSPanel {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView], backing: backing, defer: flag)
        
        // Float above everything
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Transparent background
        self.backgroundColor = .clear
        self.isOpaque = false
        // Disable system shadow to avoid square artifacts (SwiftUI handles the orb shadow)
        self.hasShadow = false
        
        // Allow clicks but don't steal focus
        self.becomesKeyOnlyIfNeeded = true
    }
    
    override var canBecomeKey: Bool {
        return false // Don't steal focus!
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

// Manager to handle showing/hiding the window
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    private var window: OverlayWindow?
    
    func setup() {
        // Create the window
        let contentView = ContentView()
            .edgesIgnoringSafeArea(.all) // Ensure content fills the frame
            
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor // Ensure hosting view is clear
        
        // Ensure the window itself is fully transparent
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), // Increased to allow glow
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear // Crucial
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = false
        
        window.contentViewController = hostingController
        self.window = window
    }
    
    func show() {
        guard let window = window else { return }
        
        // Position at mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let newOrigin = CGPoint(x: mouseLocation.x + 15, y: mouseLocation.y - 60)
        window.setFrameOrigin(newOrigin)
        
        window.orderFront(nil)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    func toggle() {
        guard let window = window else { return }
        if window.isVisible {
            hide()
        } else {
            show()
        }
    }
}

// Helper for vibrant background
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
