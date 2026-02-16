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
        
        // Position at Mouse Cursor
        let mouseLocation = NSEvent.mouseLocation
        // Offset so the 100x100 window is centered relative to the cursor but slightly above/right
        // Center of window is (50, 50). We want that center to be at (mouse.x + 20, mouse.y - 20)
        // Origin = Center - (Width/2, Height/2)
        // Origin.x = (mouse.x + 20) - 50 = mouse.x - 30
        // Origin.y = (mouse.y - 20) - 50 = mouse.y - 70
        let newOrigin = CGPoint(x: mouseLocation.x - 30, y: mouseLocation.y - 70)
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
