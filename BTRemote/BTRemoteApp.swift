import SwiftUI

@main
struct BTRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var lowEnergy: HIDPeripheral
    @StateObject private var central: HIDCentral
    @StateObject private var coordinator: EdgeSwitchCoordinator
    @StateObject private var deviceNames = DeviceNameStore()
    @Environment(\.openWindow) private var openWindow

    init() {
        UserDefaults.standard.register(defaults: [AppSettings.useServiceChangedKey: true])
        let peripheral = HIDPeripheral()
        let central = HIDCentral()
        let coordinator = EdgeSwitchCoordinator(lowEnergy: peripheral, central: central)
        _lowEnergy = StateObject(wrappedValue: peripheral)
        _central = StateObject(wrappedValue: central)
        _coordinator = StateObject(wrappedValue: coordinator)
        AppDelegate.coordinator = coordinator
    }

    var body: some Scene {
        WindowGroup(id: "controls") {
            ContentView()
                .modifier(AppEnvironment(lowEnergy: lowEnergy, central: central, names: deviceNames, coordinator: coordinator))
        }
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)
        Settings {
            LayoutSettingsView()
                .environmentObject(coordinator)
                .frame(minWidth: 420, idealWidth: 480, maxWidth: 640, minHeight: 480, idealHeight: 600)
        }
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)
        MenuBarExtra {
            Text(coordinator.isRemote ? L10n.Layout.remote : L10n.Layout.local)
            Text(verbatim: coordinator.companionStatus)
            Text(verbatim: coordinator.shortcutLabel)
            Button(L10n.Layout.openControls) {
                openWindow(id: "controls")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(coordinator.isRemote ? L10n.Layout.returnToMac : L10n.Layout.switchToPC) { coordinator.toggle() }
                .disabled(!coordinator.permissionGranted || (!coordinator.isRemote && !coordinator.targetAvailable))
            Toggle(L10n.Layout.lock, isOn: $coordinator.locked)
            Divider()
            Button(L10n.Layout.quit) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: coordinator.isRemote ? "keyboard.fill" : "keyboard")
                .accessibilityLabel(coordinator.isRemote ? L10n.Layout.remote : L10n.Layout.local)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var coordinator: EdgeSwitchCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--cursor-spike") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { CursorSpike.run() }
        } else { Self.coordinator?.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.coordinator?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct AppEnvironment: ViewModifier {
    @ObservedObject var lowEnergy: HIDPeripheral
    @ObservedObject var central: HIDCentral
    @ObservedObject var names: DeviceNameStore
    @ObservedObject var coordinator: EdgeSwitchCoordinator

    func body(content: Content) -> some View {
        content
            .environmentObject(lowEnergy)
            .environmentObject(central)
            .environmentObject(names)
            .environmentObject(coordinator)
            .environmentObject(coordinator.directInput)
            .environment(\.hid, HIDInput.make(lowEnergy: lowEnergy, central: central))
    }
}
