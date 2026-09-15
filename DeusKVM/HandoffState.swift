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
    var heldRawKeys: Set<Keycode> = []
    var heldMediaKeys: Set<UInt16> = []
    var heldButtons: Set<Int64> = []
    var modifiers: CGEventFlags = []
    private(set) var pendingToggle = false
    private var consumedKey: UInt16?
    /// modifier transitions are represented by event flags, not the global key-state snapshot
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    init(heldKeys: Set<UInt16> = [], heldButtons: Set<Int64> = []) {
        self.heldKeys = heldKeys
        self.heldButtons = heldButtons
    }

    var isReleased: Bool {
        heldKeys.isEmpty && heldRawKeys.isEmpty && heldMediaKeys.isEmpty && heldButtons.isEmpty && modifiers
            .isDisjoint(with: ToggleShortcut.modifierMask)
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

    mutating func updateModifiers(_ flags: CGEventFlags) {
        modifiers = flags
        heldKeys.subtract(Self.modifierKeyCodes)
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
