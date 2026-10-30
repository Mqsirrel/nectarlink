import SwiftUI

/// Reusable card, pill, and glass surface modifiers matching NectarLink's design language.
struct NectarCardModifier: ViewModifier {
    let palette: Palette
    var family: ThemeFamily = .hive
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background {
                if family == .glass {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(palette.surfaceContainer.opacity(0.45))
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.surfaceContainer)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        palette.outlineVariant.opacity(family == .glass ? 0.55 : 0.35),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func nectarCard(
        palette: Palette,
        family: ThemeFamily = .hive,
        cornerRadius: CGFloat = 20
    ) -> some View {
        modifier(NectarCardModifier(palette: palette, family: family, cornerRadius: cornerRadius))
    }
}
