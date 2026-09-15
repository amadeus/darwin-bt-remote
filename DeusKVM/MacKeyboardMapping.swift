import Carbon
import CoreGraphics

extension KeyboardModifiers {
    init(eventFlags flags: CGEventFlags) {
        self.init()
        // Device-dependent bits from IOLLEvent.h preserve both sides, including AltGr.
        // Synthetic Quartz events can carry only aggregate flags; retain a left-side fallback.
        add(flags, aggregate: .maskControl, bits: (0x0001, 0x2000), modifiers: (.leftCtrl, .rightCtrl))
        add(flags, aggregate: .maskShift, bits: (0x0002, 0x0004), modifiers: (.leftShift, .rightShift))
        add(flags, aggregate: .maskAlternate, bits: (0x0020, 0x0040), modifiers: (.leftAlt, .rightAlt))
        add(flags, aggregate: .maskCommand, bits: (0x0008, 0x0010), modifiers: (.leftGUI, .rightGUI))
    }

    private mutating func add(
        _ flags: CGEventFlags, aggregate: CGEventFlags, bits: (UInt64, UInt64), modifiers: (Self, Self)
    ) {
        guard flags.contains(aggregate) else { return }
        let sides = flags.rawValue & (bits.0 | bits.1)
        if sides & bits.0 != 0 || sides == 0 { insert(modifiers.0) }
        if sides & bits.1 != 0 { insert(modifiers.1) }
    }
}

extension Keycode {
    init?(macVirtualKey key: UInt16, keyboardType: UInt32 = 0) {
        if KBGetLayoutType(Int16(truncatingIfNeeded: keyboardType)) == kKeyboardISO {
            if key == 0x0A { self = .grave; return }
            if key == 0x32 { self = .nonUSBackslash; return }
        }
        guard let code = Self.macVirtualKeys[key] else { return nil }
        self = code
    }

    /// Physical virtual-key positions from HIToolbox/Events.h, not translated characters.
    /// Windows applies its own keyboard layout. Fn is consumed by macOS to produce
    /// the resulting key (for example Fn+Backspace -> forward Delete).
    static let macVirtualKeys: [UInt16: Keycode] = [
        0x00: .a, 0x0B: .b, 0x08: .c, 0x02: .d, 0x0E: .e, 0x03: .f, 0x05: .g, 0x04: .h,
        0x22: .i, 0x26: .j, 0x28: .k, 0x25: .l, 0x2E: .m, 0x2D: .n, 0x1F: .o, 0x23: .p,
        0x0C: .q, 0x0F: .r, 0x01: .s, 0x11: .t, 0x20: .u, 0x09: .v, 0x0D: .w, 0x07: .x,
        0x10: .y, 0x06: .z,
        0x12: .digit1, 0x13: .digit2, 0x14: .digit3, 0x15: .digit4, 0x17: .digit5,
        0x16: .digit6, 0x1A: .digit7, 0x1C: .digit8, 0x19: .digit9, 0x1D: .digit0,
        0x24: .return, 0x35: .escape, 0x33: .backspace, 0x30: .tab, 0x31: .space,
        0x1B: .minus, 0x18: .equal, 0x21: .leftBracket, 0x1E: .rightBracket,
        0x2A: .backslash, 0x29: .semicolon, 0x27: .quote, 0x32: .grave,
        0x2B: .comma, 0x2F: .period, 0x2C: .slash, 0x39: .capsLock,
        0x7A: .f1, 0x78: .f2, 0x63: .f3, 0x76: .f4, 0x60: .f5, 0x61: .f6,
        0x62: .f7, 0x64: .f8, 0x65: .f9, 0x6D: .f10, 0x67: .f11, 0x6F: .f12,
        0x69: .f13, 0x6B: .f14, 0x71: .f15, 0x6A: .f16,
        0x40: .f17, 0x4F: .f18, 0x50: .f19, 0x5A: .f20,
        0x72: .insert, 0x73: .home, 0x74: .pageUp, 0x75: .deleteForward, 0x77: .end, 0x79: .pageDown,
        0x7C: .rightArrow, 0x7B: .leftArrow, 0x7D: .downArrow, 0x7E: .upArrow,
        0x41: .keypadDecimal, 0x43: .keypadMultiply, 0x45: .keypadPlus, 0x47: .numLock,
        0x4B: .keypadDivide, 0x4C: .keypadEnter, 0x34: .keypadEnter, 0x4E: .keypadMinus, 0x51: .keypadEqual,
        0x52: .keypad0, 0x53: .keypad1, 0x54: .keypad2, 0x55: .keypad3, 0x56: .keypad4,
        0x57: .keypad5, 0x58: .keypad6, 0x59: .keypad7, 0x5B: .keypad8, 0x5C: .keypad9,
        0x0A: .nonUSBackslash, 0x5D: .international3, 0x5E: .international1,
        0x5F: .keypadComma, 0x66: .lang2, 0x68: .lang1,
        0x48: .volumeUp, 0x49: .volumeDown, 0x4A: .mute, 0x6E: .application, 0x7F: .power
    ]
}
