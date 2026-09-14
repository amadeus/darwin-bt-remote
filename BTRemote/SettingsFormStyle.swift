import SwiftUI

extension View {
    /// Reduce the grouped form's built-in 20-point inset to 10 points.
    @ViewBuilder
    func settingsFormStyle() -> some View {
        if #available(macOS 14.0, *) {
            formStyle(.grouped)
                .contentMargins(.horizontal, -10, for: .scrollContent)
                .contentMargins(.horizontal, -10, for: .scrollIndicators)
        } else {
            formStyle(.grouped)
        }
    }
}
