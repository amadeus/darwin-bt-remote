import SwiftUI

extension View {
    /// The grouped form already supplies a 20-point inset at compact window widths.
    @ViewBuilder
    func settingsFormStyle() -> some View {
        if #available(macOS 14.0, *) {
            formStyle(.grouped)
                .contentMargins(.horizontal, 0, for: .scrollContent)
        } else {
            formStyle(.grouped)
        }
    }
}
