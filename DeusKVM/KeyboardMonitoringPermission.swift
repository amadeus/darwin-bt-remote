import AppKit
import IOKit.hidsystem

enum KeyboardMonitoringPermission {
    @MainActor
    static func request() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
