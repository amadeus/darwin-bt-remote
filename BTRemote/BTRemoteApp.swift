import SwiftUI

@main
struct BTRemoteApp: App {
    @StateObject private var lowEnergy = HIDPeripheral()
    @StateObject private var central = HIDCentral()
    @StateObject private var deviceNames = DeviceNameStore()

    init() {
        UserDefaults.standard.register(defaults: [AppSettings.useServiceChangedKey: true])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lowEnergy)
                .environmentObject(central)
                .environmentObject(deviceNames)
                .environment(\.hid, HIDInput.make(lowEnergy: lowEnergy, central: central))
                .onAppear {
                    lowEnergy.start()
                    central.start()
                }
        }
    }
}
