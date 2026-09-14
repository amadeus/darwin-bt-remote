import CoreBluetooth
import Foundation

/// Connection readiness, independent of whether input is currently on Mac or PC.
enum StatusBarConnectionState: Equatable {
    case disabled, unavailable, searching, connecting, ready

    struct Link {
        var target: UUID?
        var subscribers: Set<UUID> = []
        var companions: Set<UUID> = []
        var lastSeen: [UUID: TimeInterval] = [:]
    }

    static func resolve(
        enabled: Bool, bluetooth: CBManagerState, link: Link, now: TimeInterval
    ) -> Self {
        guard enabled else { return .disabled }
        guard bluetooth == .poweredOn else { return .unavailable }
        if let target = link.target, link.companions.contains(target), let seen = link.lastSeen[target], now - seen < 10 {
            return .ready
        }
        return link.target != nil || !link.subscribers.isEmpty || !link.companions.isEmpty ? .connecting : .searching
    }

    func symbol(isRemote: Bool) -> String {
        switch self {
        case .disabled: "pause.circle"
        case .unavailable: "antenna.radiowaves.left.and.right.slash"
        case .searching: "antenna.radiowaves.left.and.right"
        case .connecting: "arrow.triangle.2.circlepath"
        case .ready: isRemote ? "keyboard.fill" : "keyboard"
        }
    }

    var label: String {
        switch self {
        case .disabled: "BTRemote disabled"
        case .unavailable: "BTRemote — Bluetooth unavailable"
        case .searching: "BTRemote — searching for a PC"
        case .connecting: "BTRemote — connecting to PC"
        case .ready: "BTRemote ready"
        }
    }
}
