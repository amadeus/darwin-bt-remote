import CoreGraphics
import Foundation

struct ToggleShortcut: Equatable, Sendable {
    var keyCode: UInt16 = 53
    var modifiers: UInt64 = CGEventFlags.maskSecondaryFn.rawValue
    var enabled = true

    static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]

    func matches(key: UInt16, flags: CGEventFlags) -> Bool {
        enabled && key == keyCode && flags.intersection(Self.modifierMask).rawValue == modifiers
    }
}

/// tracks physical releases without changing the existing HID translation
struct HandoffState: Sendable {
    var heldKeys: Set<UInt16> = []
    var heldButtons: Set<Int64> = []
    var modifiers: CGEventFlags = []
    private(set) var pendingToggle = false
    private var consumedKey: UInt16?

    init(heldKeys: Set<UInt16> = [], heldButtons: Set<Int64> = []) {
        self.heldKeys = heldKeys
        self.heldButtons = heldButtons
    }

    var isReleased: Bool {
        heldKeys.isEmpty && heldButtons.isEmpty && modifiers.isDisjoint(with: ToggleShortcut.modifierMask)
    }

    mutating func key(code: UInt16, down: Bool, repeatEvent: Bool, flags: CGEventFlags, shortcut: ToggleShortcut) -> Bool {
        modifiers = flags
        if down { heldKeys.insert(code) } else { heldKeys.remove(code) }
        if consumedKey == code {
            if !down { consumedKey = nil }
            return true
        }
        if down, !repeatEvent, shortcut.matches(key: code, flags: flags) {
            pendingToggle = true
            consumedKey = code
            return true
        }
        return false
    }

    mutating func requestToggle() {
        pendingToggle = true
    }

    mutating func takeToggle() -> Bool {
        guard pendingToggle, isReleased else { return false }
        pendingToggle = false
        return true
    }

    mutating func cancel() {
        pendingToggle = false
    }
}
