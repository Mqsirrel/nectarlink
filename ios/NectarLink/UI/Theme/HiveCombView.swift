import SwiftUI

/// Animated hexagonal honeycomb backdrop for the Hive theme (`Tokens.comb*`).
struct HiveCombView: View {
    let palette: Palette
    let isDark: Bool
    var isConnected: Bool = true
    var isTransferring: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: Double(Tokens.combFrameMs) / 1000.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                drawHoneycomb(canvas: &canvas, size: size, time: t)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func drawHoneycomb(canvas: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let r = Tokens.combCellPt
        let dx = r * sqrt(3.0)
        let dy = r * 1.5
        let cols = Int(ceil(size.width / dx)) + 2
        let rows = Int(ceil(size.height / dy)) + 2

        let breathPhase = (sin(time * (2.0 * .pi / Tokens.combBreathSeconds)) + 1.0) * 0.5
        let pulsePeriod = isTransferring ? (Tokens.combPulseSeconds * 0.55) : Tokens.combPulseSeconds
        let pulsePhase = (sin(time * (2.0 * .pi / pulsePeriod)) + 1.0) * 0.5

        let baseAlpha = isDark ? Tokens.combLineAlphaDark : Tokens.combLineAlphaLight
        let glowAlpha = (isDark ? Tokens.combGlowAlphaDark : Tokens.combGlowAlphaLight)
            * (isConnected ? (0.45 + 0.35 * breathPhase) : 0.18)

        // Radial warm glow near top-centre
        let glowCenter = CGPoint(x: size.width * 0.5, y: size.height * (0.22 + 0.04 * pulsePhase))
        let glowRadius = max(size.width, size.height) * 0.65
        let gradient = Gradient(colors: [
            palette.primary.opacity(glowAlpha * 0.28),
            palette.primaryContainer.opacity(glowAlpha * 0.10),
            Color.clear
        ])
        canvas.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                gradient,
                center: glowCenter,
                startRadius: 8,
                endRadius: glowRadius
            )
        )

        var gridPath = Path()
        for row in -1..<rows {
            let y = CGFloat(row) * dy
            let xOffset = (row & 1 == 0) ? 0.0 : (dx * 0.5)
            for col in -1..<cols {
                let x = CGFloat(col) * dx + xOffset
                addHexagon(to: &gridPath, center: CGPoint(x: x, y: y), radius: r * 0.94)
            }
        }

        canvas.stroke(
            gridPath,
            with: .color(palette.outlineVariant.opacity(baseAlpha)),
            lineWidth: 1.0
        )
    }

    private func addHexagon(to path: inout Path, center: CGPoint, radius: CGFloat) {
        for i in 0..<6 {
            let angle = CGFloat(i) * (.pi / 3.0) - (.pi / 6.0)
            let pt = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
    }
}
