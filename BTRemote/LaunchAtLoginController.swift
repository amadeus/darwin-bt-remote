import ServiceManagement
import SwiftUI

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var busy = false
    @Published var error: String?

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    @discardableResult
    func setEnabled(_ value: Bool) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false; refresh() }
        do {
            if value {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status != .notRegistered {
                try await SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
