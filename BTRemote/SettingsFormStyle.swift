import SwiftUI

extension View {
    /// Keep the native scroll viewport flush with its pane so content can
    /// continue beneath the titlebar and participate in the scroll edge effect.
    @ViewBuilder
    func settingsFormStyle() -> some View {
        if #available(macOS 14.0, *) {
            formStyle(.grouped)
                .softTopScrollEdge()
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .contentMargins(.horizontal, 0, for: .scrollIndicators)
                .contentMargins(.bottom, 10, for: .scrollIndicators)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        } else {
            formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func softTopScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            // Use the native progressive blur beneath the window header and tabs.
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
