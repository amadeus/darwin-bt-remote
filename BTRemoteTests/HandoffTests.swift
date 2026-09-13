import CoreGraphics
import XCTest

final class HandoffTests: XCTestCase {
    func testHotkeyWaitsForKeyAndModifierReleaseAndDoesNotRepeat() {
        var state = HandoffState()
        let shortcut = ToggleShortcut()
        XCTAssertTrue(state.key(code: 53, down: true, repeatEvent: false, flags: .maskSecondaryFn, shortcut: shortcut))
        XCTAssertFalse(state.takeToggle())
        XCTAssertTrue(state.key(code: 53, down: true, repeatEvent: true, flags: .maskSecondaryFn, shortcut: shortcut))
        XCTAssertTrue(state.key(code: 53, down: false, repeatEvent: false, flags: .maskSecondaryFn, shortcut: shortcut))
        XCTAssertFalse(state.takeToggle())
        state.modifiers = []
        XCTAssertTrue(state.takeToggle())
        XCTAssertFalse(state.takeToggle())
    }

    func testUnmappedHeldKeyAndButtonAlsoDelayHandoff() {
        var state = HandoffState(heldKeys: [120], heldButtons: [1])
        state.requestToggle()
        XCTAssertFalse(state.takeToggle())
        XCTAssertFalse(state.key(code: 120, down: false, repeatEvent: false, flags: [], shortcut: ToggleShortcut()))
        XCTAssertFalse(state.takeToggle())
        state.heldButtons.remove(1)
        XCTAssertTrue(state.takeToggle())
    }

    func testOrdinaryKeyReleasesRemainRoutedAndCapsLockDoesNotBlock() {
        var state = HandoffState()
        let shortcut = ToggleShortcut()
        XCTAssertFalse(state.key(code: 0, down: true, repeatEvent: false, flags: [], shortcut: shortcut))
        state.requestToggle()
        XCTAssertFalse(state.takeToggle())
        XCTAssertFalse(state.key(code: 0, down: false, repeatEvent: false, flags: .maskAlphaShift, shortcut: shortcut))
        XCTAssertTrue(state.takeToggle())
    }

    func testShortcutRequiresExactModifiers() {
        var state = HandoffState()
        XCTAssertFalse(state.key(code: 53, down: true, repeatEvent: false, flags: [.maskSecondaryFn, .maskShift], shortcut: .init()))
        XCTAssertFalse(state.pendingToggle)
    }
}
