import Foundation
import SwiftUI

extension HIDInput {
    static var unavailable: HIDInput {
        HIDInput(
            sendMouse: { _ in }, sendKeyboard: { _ in }, sendConsumer: { _ in },
            isActive: false, isConnected: false, activeError: nil
        )
    }

    @MainActor
    static func make(lowEnergy: HIDPeripheral, central: HIDCentral) -> HIDInput {
        HIDInput(
            sendMouse: { lowEnergy.sendMouse($0) },
            sendKeyboard: { lowEnergy.sendKeyboard($0) },
            sendConsumer: { lowEnergy.sendConsumer($0) },
            isActive: lowEnergy.isHIDServiceAdded,
            isConnected: lowEnergy.hostPolicy.target != nil,
            activeError: lowEnergy.lastError ?? central.lastError
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
