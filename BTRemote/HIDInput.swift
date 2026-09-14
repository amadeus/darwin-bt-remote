import Foundation
import SwiftUI

/// shares the active HID backend with input capture and status views
struct HIDInput {
    let sendMouse: (MouseReport) -> Void
    let sendKeyboard: (KeyboardReport) -> Void
    let sendConsumer: (ConsumerReport) -> Void
    let updateBattery: (UInt8) -> Void
    let isActive: Bool
    let isConnected: Bool
    let activeError: String?
    let batteryLevel: UInt8
}

extension HIDInput {
    static var unavailable: HIDInput {
        HIDInput(
            sendMouse: { _ in }, sendKeyboard: { _ in }, sendConsumer: { _ in }, updateBattery: { _ in },
            isActive: false, isConnected: false, activeError: nil, batteryLevel: 0
        )
    }

    @MainActor
    static func make(lowEnergy: HIDPeripheral, central: HIDCentral) -> HIDInput {
        HIDInput(
            sendMouse: { lowEnergy.sendMouse($0) },
            sendKeyboard: { lowEnergy.sendKeyboard($0) },
            sendConsumer: { lowEnergy.sendConsumer($0) },
            updateBattery: { lowEnergy.updateBatteryLevel($0) },
            isActive: lowEnergy.isHIDServiceAdded,
            isConnected: lowEnergy.connectedCentrals.contains { !lowEnergy.inactiveCentrals.contains($0) } || !central.connected.isEmpty,
            activeError: lowEnergy.lastError ?? central.lastError,
            batteryLevel: lowEnergy.batteryLevel
        )
    }
}

private struct HIDInputKey: EnvironmentKey {
    static var defaultValue: HIDInput {
        .unavailable
    }
}

extension EnvironmentValues {
    var hid: HIDInput {
        get { self[HIDInputKey.self] }
        set { self[HIDInputKey.self] = newValue }
    }
}
