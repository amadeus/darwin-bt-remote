import AppKit
import CoreGraphics
import Darwin

/// resolves the same background cursor property used by Deskflow
@MainActor
final class CursorConcealer {
    private typealias Connection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private let connection: Connection?
    private let setProperty: SetProperty?
    private var panel: NSPanel?
    private var hidden = false
    private var origin: CGPoint?
    private(set) var parkingPoint: CGPoint?

    init() {
        let handle = dlopen(nil, RTLD_LAZY)
        connection = handle.flatMap { dlsym($0, "_CGSDefaultConnection") }.map { unsafeBitCast($0, to: Connection.self) }
        setProperty = handle.flatMap { dlsym($0, "CGSSetConnectionProperty") }.map { unsafeBitCast($0, to: SetProperty.self) }
    }

    func hide(at point: CGPoint, returningTo returnPoint: CGPoint) -> Bool {
        restore()
        guard let connection, let setProperty else { return false }
        let cid = connection()
        guard setProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0 else { return false }
        origin = returnPoint
        parkingPoint = point
        // AppKit uses bottom-left coordinates; Quartz global space starts at the primary display's top-left
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let panel = NSPanel(
            contentRect: NSRect(x: point.x, y: primaryHeight - point.y - 1, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        // a near-transparent hit-testable window prevents hover in the underlying application
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        panel.hasShadow = false
        panel.orderFrontRegardless()
        self.panel = panel
        guard CGWarpMouseCursorPosition(point) == .success,
              CGAssociateMouseAndMouseCursorPosition(0) == .success,
              CGDisplayHideCursor(CGMainDisplayID()) == .success
        else {
            restore()
            return false
        }
        hidden = true
        return true
    }

    func restore(at point: CGPoint? = nil) {
        guard origin != nil || panel != nil || hidden else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        if hidden {
            CGDisplayShowCursor(CGMainDisplayID())
            hidden = false
        }
        if let position = point ?? origin { CGWarpMouseCursorPosition(position) }
        panel?.orderOut(nil)
        panel = nil
        parkingPoint = nil
        origin = nil
        if let connection, let setProperty {
            let cid = connection()
            _ = setProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanFalse)
        }
    }
}
