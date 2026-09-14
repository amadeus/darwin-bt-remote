import SwiftUI

extension View {
    /// Keep the grouped form's side and bottom insets at 10 points.
    @ViewBuilder
    func settingsFormStyle() -> some View {
        if #available(macOS 14.0, *) {
            formStyle(.grouped)
                .contentMargins(.horizontal, -10, for: .scrollContent)
                .contentMargins(.horizontal, -10, for: .scrollIndicators)
                .padding(.bottom, -10)
        } else {
            formStyle(.grouped)
        }
    }
}
