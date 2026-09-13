import SwiftUI

enum TransportMode: String, CaseIterable, Codable {
    case classic
    case lowEnergy

    static let defaultMode: TransportMode = .lowEnergy
}

@main
struct BTRemoteApp: App {
    @StateObject private var lowEnergy = HIDPeripheral()
    @StateObject private var central = HIDCentral()
    @StateObject private var classic = HIDClassicDevice()
    @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.defaultMode.rawValue

    @StateObject private var deviceNames = DeviceNameStore()

    init() {
        UserDefaults.standard.register(defaults: [AppSettings.useServiceChangedKey: true])
    }

    private var hid: HIDInput {
        HIDInput.make(lowEnergy: lowEnergy, central: central, classic: classic, classicMode: currentMode == .classic)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lowEnergy)
                .environmentObject(central)
                .environmentObject(classic)
                .environmentObject(deviceNames)
                .environment(\.macTransport, currentMode)
                .environment(\.hid, hid)
                .onAppear { _onAppear() }
                .onChange(of: modeRaw) { _ in _modeChanged() }
        }
    }

    private var currentMode: TransportMode {
        TransportMode(rawValue: modeRaw) ?? .defaultMode
    }

    private func _onAppear() {
        switch currentMode {
        case .classic:
            classic.start()
        case .lowEnergy:
            lowEnergy.start()
            central.start()
        }
    }

    private func _modeChanged() {
        // tear down the previously-active backend to prevent race
        lowEnergy.stop()
        classic.stop()

        switch currentMode {
        case .classic:
            classic.start()
        case .lowEnergy:
            lowEnergy.start()
            central.start()
        }
    }
}

private struct MacTransportKey: EnvironmentKey {
    static let defaultValue: TransportMode = .defaultMode
}

extension EnvironmentValues {
    var macTransport: TransportMode {
        get { self[MacTransportKey.self] }
        set { self[MacTransportKey.self] = newValue }
    }
}
