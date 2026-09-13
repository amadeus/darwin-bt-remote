import Foundation

enum AppSettings {
    static let touchpadSensitivityKey = "BTRemote.touchpadSensitivity"
    static let scrollSensitivityKey = "BTRemote.scrollSensitivity"
    static let autoAdvertiseKey = "BTRemote.autoAdvertise"
    static let developerModeKey = "BTRemote.developerMode"
    static let useServiceChangedKey = "BTRemote.useServiceChanged"
    static let deviceNamesKey = "BTRemote.deviceNames"
    static let hasSeenWelcomeKey = "BTRemote.hasSeenWelcome"
    static let liveTypingKey = "BTRemote.liveTyping"
    static let remoteModeKey = "BTRemote.remoteMode"
    static let advertisedNameKey = "BTRemote.advertisedName"

    static let edgeSwitchEnabledKey = "BTRemote.edgeSwitchEnabled"
    static let edgeDisplayUUIDKey = "BTRemote.edgeDisplayUUID"
    static let edgeSideKey = "BTRemote.edgeSide"
    static let switchDelayMsKey = "BTRemote.switchDelayMs"
    static let cornerSizePxKey = "BTRemote.cornerSizePx"
    static let toggleKeyCodeKey = "BTRemote.toggleKeyCode"
    static let toggleModifiersKey = "BTRemote.toggleModifiers"
    static let toggleHotkeyEnabledKey = "BTRemote.toggleHotkeyEnabled"
    static let defaultSwitchDelay = 250.0
    static let defaultCornerSize = 0.0

    static let maxAdvertisedNameLength = 26

    static let repoURL = URL(string: "https://github.com/jqssun/darwin-bt-remote")!
    static let instructionsURL = URL(string: "https://github.com/jqssun/darwin-bt-remote/blob/main/README.md")!

    static let defaultPointerSensitivity = 5.0
    static let pointerSensitivityRange = 0.5 ... 10.0
    static let defaultScrollSensitivity = 1.0
    static let scrollSensitivityRange = 0.5 ... 3.0
}
