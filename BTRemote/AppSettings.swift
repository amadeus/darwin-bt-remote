import Foundation

enum AppSettings {
    static let allowedHostsKey = "BTRemote.allowedHosts"
    static let autoAdvertiseKey = "BTRemote.autoAdvertise"
    static let developerModeKey = "BTRemote.developerMode"
    static let useServiceChangedKey = "BTRemote.useServiceChanged"
    static let deviceNamesKey = "BTRemote.deviceNames"
    static let hasSeenWelcomeKey = "BTRemote.hasSeenWelcome"
    static let advertisedNameKey = "BTRemote.advertisedName"

    static let invertVerticalScrollKey = "BTRemote.invertVerticalScroll"
    static let invertHorizontalScrollKey = "BTRemote.invertHorizontalScroll"

    static let edgeSwitchEnabledKey = "BTRemote.edgeSwitchEnabled"
    static let edgeDisplayUUIDKey = "BTRemote.edgeDisplayUUID"
    static let edgeSideKey = "BTRemote.edgeSide"
    static let cornerSizePxKey = "BTRemote.cornerSizePx"
    static let toggleKeyCodeKey = "BTRemote.toggleKeyCode"
    static let toggleModifiersKey = "BTRemote.toggleModifiers"
    static let toggleHotkeyEnabledKey = "BTRemote.toggleHotkeyEnabled"
    static let defaultCornerSize = 0.0

    static let maxAdvertisedNameLength = 26

    static let repoURL = URL(string: "https://github.com/jqssun/darwin-bt-remote")!
}
