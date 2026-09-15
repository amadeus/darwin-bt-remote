import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

    static func request() {
        // Request the event-posting access used by capture, rather than only opening Settings.
        if !CGPreflightPostEventAccess() {
            CGRequestPostEventAccess()
        }

        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
