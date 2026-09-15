import SwiftUI

extension View {
    /// Keep the grouped form's side and bottom insets at 10 points.
    @ViewBuilder
    func settingsFormStyle() -> some View {
        if #available(macOS 14.0, *) {
            formStyle(.grouped)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .contentMargins(.horizontal, 10, for: .scrollIndicators)
                .contentMargins(.bottom, 10, for: .scrollIndicators)
                // Expand the viewport, not its scrollable content, to reduce
                // the native 20-point grouped inset without horizontal overflow.
                .padding(.horizontal, -10)
                .padding(.bottom, -10)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // Let the native scroll view extend beneath the translucent titlebar.
            // An outer clip cuts it off at the content safe-area edge instead.
        } else {
            formStyle(.grouped)
        }
    }
}
