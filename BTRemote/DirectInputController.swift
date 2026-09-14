import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DirectInputController: ObservableObject {
    @Published private(set) var isCapturing = false

    private var pressedKeys: Set<Keycode> = []
    private var pressedMouseButtons: MouseButtons = []
    private var modifiers: KeyboardModifiers = []

    private var sendKeyboard: ((KeyboardReport) -> Void)?
    private var sendMouse: ((MouseReport) -> Void)?

    /// retains the upstream report translation; tap and cursor lifetime belong to the coordinator
    func start(_ hid: HIDInput) {
        stop()
        sendKeyboard = hid.sendKeyboard
        sendMouse = hid.sendMouse
        isCapturing = true
    }

    func stop() {
        pressedKeys.removeAll()
        pressedMouseButtons = []
        modifiers = []
        sendKeyboard?(.zero)
        sendMouse?(.zero)
        sendKeyboard = nil
        sendMouse = nil
        isCapturing = false
    }

    func handle(_ event: DirectInputEvent) {
        guard isCapturing else { return }

        modifiers = event.modifiers

        switch event.kind {
        case let .keyDown(key):
            pressedKeys.insert(key)
            sendKeyboardReport()
        case let .keyUp(key):
            pressedKeys.remove(key)
            sendKeyboardReport()
        case .flagsChanged:
            sendKeyboardReport()
        case let .mouseMove(dx, dy):
            sendMouse?(MouseReport(buttons: pressedMouseButtons, dX: dx, dY: dy))
        case let .mouseButton(button, isDown):
            if isDown {
                pressedMouseButtons.insert(button)
            } else {
                pressedMouseButtons.remove(button)
            }
            sendMouse?(MouseReport(buttons: pressedMouseButtons))
        case let .scroll(wheel, pan):
            sendMouse?(MouseReport(buttons: pressedMouseButtons, wheel: wheel, pan: pan))
            sendMouse?(MouseReport(buttons: pressedMouseButtons))
        }
    }

    private func sendKeyboardReport() {
        sendKeyboard?(KeyboardReport(modifiers: modifiers, keys: Array(pressedKeys).prefix(6).map(\.self)))
    }
}
