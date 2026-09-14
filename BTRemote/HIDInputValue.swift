import Foundation

/// shares the active HID backend with input capture and status views
struct HIDInput {
    let sendMouse: (MouseReport) -> Void
    let sendKeyboard: (KeyboardReport) -> Void
    let sendConsumer: (ConsumerReport) -> Void
    let isActive: Bool
    let isConnected: Bool
    let activeError: String?
}
