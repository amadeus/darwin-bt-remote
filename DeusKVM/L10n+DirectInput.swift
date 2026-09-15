import SwiftUI

extension L10n {
    enum DirectInput {
        static var releaseHint: LocalizedStringKey {
            "direct_input.release_hint"
        }

        static var iosNoDevice: LocalizedStringKey {
            "direct_input.ios_no_device"
        }

        static var releaseHintString: String {
            String(localized: "direct_input.release_hint")
        }

        static var captureFailedString: String {
            String(localized: "direct_input.capture_failed")
        }

        static var permissionTitle: LocalizedStringKey {
            "direct_input.permission_title"
        }

        static var permissionMessage: LocalizedStringKey {
            "direct_input.permission_message"
        }

        static var openSettings: LocalizedStringKey {
            "direct_input.open_settings"
        }

        static var enable: LocalizedStringKey {
            "direct_input.enable"
        }

        static var connectedPromptTitle: LocalizedStringKey {
            "direct_input.connected_prompt_title"
        }

        static var connectedPromptMessage: LocalizedStringKey {
            "direct_input.connected_prompt_message"
        }
    }
}
