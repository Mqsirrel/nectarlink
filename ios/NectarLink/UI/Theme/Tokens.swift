// SPDX-License-Identifier: MPL-2.0
// Generated from docs/design/tokens.json by `cargo xtask tokens`. Do not edit.
import SwiftUI

extension Color {
    public init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Material color roles of one theme variant.
public struct Palette: Equatable, Sendable {
    public let primary: Color
    public let onPrimary: Color
    public let primaryContainer: Color
    public let onPrimaryContainer: Color
    public let secondaryContainer: Color
    public let onSecondaryContainer: Color
    public let surface: Color
    public let surfaceContainerLow: Color
    public let surfaceContainer: Color
    public let surfaceContainerHigh: Color
    public let surfaceContainerHighest: Color
    public let onSurface: Color
    public let onSurfaceVariant: Color
    public let outline: Color
    public let outlineVariant: Color
}

/// A Bloom color preset: its seed swatch and light and dark palettes.
public struct Seed: Equatable, Sendable {
    public let color: Color
    public let seedRgb: UInt32
    public let light: Palette
    public let dark: Palette
}

public enum Tokens {
    public static let defaultSeed = "honey"

    public static let bloomSeeds: [String: Seed] = [
        "black": Seed(
            color: Color(hex: 0x18181C),
            seedRgb: 0xFF18181C,
            light: Palette(
                primary: Color(hex: 0x18181C),
                onPrimary: Color(hex: 0xFFFFFF),
                primaryContainer: Color(hex: 0xDCDCE2),
                onPrimaryContainer: Color(hex: 0x141418),
                secondaryContainer: Color(hex: 0xE5E5EB),
                onSecondaryContainer: Color(hex: 0x18181C),
                surface: Color(hex: 0xFAFAFC),
                surfaceContainerLow: Color(hex: 0xF4F4F7),
                surfaceContainer: Color(hex: 0xEEEEF2),
                surfaceContainerHigh: Color(hex: 0xE7E7EC),
                surfaceContainerHighest: Color(hex: 0xE0E0E6),
                onSurface: Color(hex: 0x111114),
                onSurfaceVariant: Color(hex: 0x43434A),
                outline: Color(hex: 0x73737C),
                outlineVariant: Color(hex: 0xC7C7D0)
            ),
            dark: Palette(
                primary: Color(hex: 0xE2E2EA),
                onPrimary: Color(hex: 0x141418),
                primaryContainer: Color(hex: 0x2E2E36),
                onPrimaryContainer: Color(hex: 0xF0F0F5),
                secondaryContainer: Color(hex: 0x26262E),
                onSecondaryContainer: Color(hex: 0xE2E2EA),
                surface: Color(hex: 0x0A0A0C),
                surfaceContainerLow: Color(hex: 0x060608),
                surfaceContainer: Color(hex: 0x141418),
                surfaceContainerHigh: Color(hex: 0x1E1E24),
                surfaceContainerHighest: Color(hex: 0x282830),
                onSurface: Color(hex: 0xECECF0),
                onSurfaceVariant: Color(hex: 0xC2C2CA),
                outline: Color(hex: 0x8E8E98),
                outlineVariant: Color(hex: 0x3E3E48)
            )
        ),
        "honey": Seed(
            color: Color(hex: 0xB7791F),
            seedRgb: 0xFFB7791F,
            light: Palette(
                primary: Color(hex: 0x8A5100),
                onPrimary: Color(hex: 0xFFFFFF),
                primaryContainer: Color(hex: 0xFFDDB8),
                onPrimaryContainer: Color(hex: 0x2C1600),
                secondaryContainer: Color(hex: 0xF3E0CB),
                onSecondaryContainer: Color(hex: 0x261A0C),
                surface: Color(hex: 0xFFF8F3),
                surfaceContainerLow: Color(hex: 0xFBF2EB),
                surfaceContainer: Color(hex: 0xF5ECE4),
                surfaceContainerHigh: Color(hex: 0xEFE6DE),
                surfaceContainerHighest: Color(hex: 0xE9E1D9),
                onSurface: Color(hex: 0x1F1B16),
                onSurfaceVariant: Color(hex: 0x51453A),
                outline: Color(hex: 0x837468),
                outlineVariant: Color(hex: 0xD5C3B5)
            ),
            dark: Palette(
                primary: Color(hex: 0xFFB95F),
                onPrimary: Color(hex: 0x4A2800),
                primaryContainer: Color(hex: 0x693C00),
                onPrimaryContainer: Color(hex: 0xFFDDB8),
                secondaryContainer: Color(hex: 0x574330),
                onSecondaryContainer: Color(hex: 0xF3E0CB),
                surface: Color(hex: 0x17130E),
                surfaceContainerLow: Color(hex: 0x120E0A),
                surfaceContainer: Color(hex: 0x241F1A),
                surfaceContainerHigh: Color(hex: 0x2E2924),
                surfaceContainerHighest: Color(hex: 0x39342E),
                onSurface: Color(hex: 0xEBE1D9),
                onSurfaceVariant: Color(hex: 0xD5C3B5),
                outline: Color(hex: 0x9E8E81),
                outlineVariant: Color(hex: 0x51453A)
            )
        ),
        "lavender": Seed(
            color: Color(hex: 0x7E6AA8),
            seedRgb: 0xFF7E6AA8,
            light: Palette(
                primary: Color(hex: 0x65558F),
                onPrimary: Color(hex: 0xFFFFFF),
                primaryContainer: Color(hex: 0xE9DDFF),
                onPrimaryContainer: Color(hex: 0x201047),
                secondaryContainer: Color(hex: 0xE8DEF8),
                onSecondaryContainer: Color(hex: 0x1D192B),
                surface: Color(hex: 0xFDF7FF),
                surfaceContainerLow: Color(hex: 0xF7F2FA),
                surfaceContainer: Color(hex: 0xF2ECF4),
                surfaceContainerHigh: Color(hex: 0xECE6EE),
                surfaceContainerHighest: Color(hex: 0xE6E0E9),
                onSurface: Color(hex: 0x1D1B20),
                onSurfaceVariant: Color(hex: 0x49454E),
                outline: Color(hex: 0x7A757F),
                outlineVariant: Color(hex: 0xCAC4CF)
            ),
            dark: Palette(
                primary: Color(hex: 0xCFBDFE),
                onPrimary: Color(hex: 0x36275D),
                primaryContainer: Color(hex: 0x4D3D75),
                onPrimaryContainer: Color(hex: 0xE9DDFF),
                secondaryContainer: Color(hex: 0x4A4458),
                onSecondaryContainer: Color(hex: 0xE8DEF8),
                surface: Color(hex: 0x141218),
                surfaceContainerLow: Color(hex: 0x0F0D13),
                surfaceContainer: Color(hex: 0x211F24),
                surfaceContainerHigh: Color(hex: 0x2B292F),
                surfaceContainerHighest: Color(hex: 0x36343A),
                onSurface: Color(hex: 0xE6E0E9),
                onSurfaceVariant: Color(hex: 0xCAC4CF),
                outline: Color(hex: 0x948F99),
                outlineVariant: Color(hex: 0x49454E)
            )
        ),
        "ocean": Seed(
            color: Color(hex: 0x3D7DA8),
            seedRgb: 0xFF3D7DA8,
            light: Palette(
                primary: Color(hex: 0x2F628C),
                onPrimary: Color(hex: 0xFFFFFF),
                primaryContainer: Color(hex: 0xCEE5FF),
                onPrimaryContainer: Color(hex: 0x001D33),
                secondaryContainer: Color(hex: 0xD5E4F7),
                onSecondaryContainer: Color(hex: 0x0E1D2A),
                surface: Color(hex: 0xF7F9FF),
                surfaceContainerLow: Color(hex: 0xF1F4FA),
                surfaceContainer: Color(hex: 0xECEEF4),
                surfaceContainerHigh: Color(hex: 0xE6E8EE),
                surfaceContainerHighest: Color(hex: 0xE0E2E8),
                onSurface: Color(hex: 0x181C20),
                onSurfaceVariant: Color(hex: 0x42474E),
                outline: Color(hex: 0x72777F),
                outlineVariant: Color(hex: 0xC2C7CF)
            ),
            dark: Palette(
                primary: Color(hex: 0x9BCBFB),
                onPrimary: Color(hex: 0x003354),
                primaryContainer: Color(hex: 0x0F4A73),
                onPrimaryContainer: Color(hex: 0xCEE5FF),
                secondaryContainer: Color(hex: 0x3B4858),
                onSecondaryContainer: Color(hex: 0xD5E4F7),
                surface: Color(hex: 0x101418),
                surfaceContainerLow: Color(hex: 0x0B0F13),
                surfaceContainer: Color(hex: 0x1C2024),
                surfaceContainerHigh: Color(hex: 0x262A2F),
                surfaceContainerHighest: Color(hex: 0x31353A),
                onSurface: Color(hex: 0xE0E2E8),
                onSurfaceVariant: Color(hex: 0xC2C7CF),
                outline: Color(hex: 0x8C9199),
                outlineVariant: Color(hex: 0x42474E)
            )
        ),
        "sage": Seed(
            color: Color(hex: 0x5B8C5A),
            seedRgb: 0xFF5B8C5A,
            light: Palette(
                primary: Color(hex: 0x3B6939),
                onPrimary: Color(hex: 0xFFFFFF),
                primaryContainer: Color(hex: 0xBCF0B4),
                onPrimaryContainer: Color(hex: 0x002204),
                secondaryContainer: Color(hex: 0xD6E8CF),
                onSecondaryContainer: Color(hex: 0x111F0F),
                surface: Color(hex: 0xF7FBF1),
                surfaceContainerLow: Color(hex: 0xF1F5EB),
                surfaceContainer: Color(hex: 0xEBEFE5),
                surfaceContainerHigh: Color(hex: 0xE6E9E0),
                surfaceContainerHighest: Color(hex: 0xE0E4DA),
                onSurface: Color(hex: 0x191D17),
                onSurfaceVariant: Color(hex: 0x424940),
                outline: Color(hex: 0x72796F),
                outlineVariant: Color(hex: 0xC2C8BD)
            ),
            dark: Palette(
                primary: Color(hex: 0xA1D39A),
                onPrimary: Color(hex: 0x0A390F),
                primaryContainer: Color(hex: 0x234F24),
                onPrimaryContainer: Color(hex: 0xBCF0B4),
                secondaryContainer: Color(hex: 0x3B4B38),
                onSecondaryContainer: Color(hex: 0xD6E8CF),
                surface: Color(hex: 0x10140F),
                surfaceContainerLow: Color(hex: 0x0C100B),
                surfaceContainer: Color(hex: 0x1D211B),
                surfaceContainerHigh: Color(hex: 0x272B25),
                surfaceContainerHighest: Color(hex: 0x32362F),
                onSurface: Color(hex: 0xE0E4DA),
                onSurfaceVariant: Color(hex: 0xC2C8BD),
                outline: Color(hex: 0x8C9388),
                outlineVariant: Color(hex: 0x424940)
            )
        ),
    ]

    public static let graphitePaper = Palette(
        primary: Color(hex: 0x1A1918),
        onPrimary: Color(hex: 0xF5F2EB),
        primaryContainer: Color(hex: 0xE8E3D7),
        onPrimaryContainer: Color(hex: 0x1A1918),
        secondaryContainer: Color(hex: 0xE8E3D7),
        onSecondaryContainer: Color(hex: 0x1A1918),
        surface: Color(hex: 0xF5F2EB),
        surfaceContainerLow: Color(hex: 0xF1EDE4),
        surfaceContainer: Color(hex: 0xF5F2EB),
        surfaceContainerHigh: Color(hex: 0xEFEBE2),
        surfaceContainerHighest: Color(hex: 0xE8E3D7),
        onSurface: Color(hex: 0x1A1918),
        onSurfaceVariant: Color(hex: 0x5E5A54),
        outline: Color(hex: 0x4A4743),
        outlineVariant: Color(hex: 0xD5CFC2)
    )

    public static let graphiteSlate = Palette(
        primary: Color(hex: 0xE8EAED),
        onPrimary: Color(hex: 0x0D0D0E),
        primaryContainer: Color(hex: 0x1A1A1D),
        onPrimaryContainer: Color(hex: 0xE8EAED),
        secondaryContainer: Color(hex: 0x1A1A1D),
        onSecondaryContainer: Color(hex: 0xE8EAED),
        surface: Color(hex: 0x0D0D0E),
        surfaceContainerLow: Color(hex: 0x0B0B0C),
        surfaceContainer: Color(hex: 0x0D0D0E),
        surfaceContainerHigh: Color(hex: 0x141416),
        surfaceContainerHighest: Color(hex: 0x1A1A1D),
        onSurface: Color(hex: 0xE8EAED),
        onSurfaceVariant: Color(hex: 0x9A9CA1),
        outline: Color(hex: 0x7E8084),
        outlineVariant: Color(hex: 0x26272A)
    )

    public static let hiveWax = Palette(
        primary: Color(hex: 0x8A5100),
        onPrimary: Color(hex: 0xFFFFFF),
        primaryContainer: Color(hex: 0xFFDDB3),
        onPrimaryContainer: Color(hex: 0x2C1600),
        secondaryContainer: Color(hex: 0xF4E3CD),
        onSecondaryContainer: Color(hex: 0x2A1F14),
        surface: Color(hex: 0xFFF8F3),
        surfaceContainerLow: Color(hex: 0xFCF2E9),
        surfaceContainer: Color(hex: 0xF8ECE1),
        surfaceContainerHigh: Color(hex: 0xF3E5D7),
        surfaceContainerHighest: Color(hex: 0xEDDDCD),
        onSurface: Color(hex: 0x1F1B16),
        onSurfaceVariant: Color(hex: 0x5C4F43),
        outline: Color(hex: 0x85766A),
        outlineVariant: Color(hex: 0xDDCBBA)
    )

    public static let hiveComb = Palette(
        primary: Color(hex: 0xFFB95F),
        onPrimary: Color(hex: 0x2C1600),
        primaryContainer: Color(hex: 0x5A3A0E),
        onPrimaryContainer: Color(hex: 0xFFDDB3),
        secondaryContainer: Color(hex: 0x2F2A24),
        onSecondaryContainer: Color(hex: 0xF0E0CC),
        surface: Color(hex: 0x121214),
        surfaceContainerLow: Color(hex: 0x151517),
        surfaceContainer: Color(hex: 0x1A1A1D),
        surfaceContainerHigh: Color(hex: 0x212124),
        surfaceContainerHighest: Color(hex: 0x29292D),
        onSurface: Color(hex: 0xEDE6DD),
        onSurfaceVariant: Color(hex: 0xABA195),
        outline: Color(hex: 0x8D8379),
        outlineVariant: Color(hex: 0x34312D)
    )

    public static let hiveWaxWarning = Color(hex: 0x7A4A00)
    public static let hiveWaxError = Color(hex: 0x9E2B25)
    public static let hiveCombWarning = Color(hex: 0xF5D58A)
    public static let hiveCombError = Color(hex: 0xF0A39C)

    /// The honeycomb backdrop (themes.hive.comb).
    public static let combCellPt: CGFloat = 24
    public static let combLineAlphaDark: Double = 0.27
    public static let combLineAlphaLight: Double = 0.11
    public static let combGlowAlphaDark: Double = 0.7
    public static let combGlowAlphaLight: Double = 0.75
    public static let combBreathSeconds: Double = 6
    public static let combPulseSeconds: Double = 4.5
    public static let combFrameMs: Int = 33

    public static let warningLight = Color(hex: 0x7D5200)
    public static let warningDark = Color(hex: 0xF2C14E)
    public static let errorLight = Color(hex: 0xBA1A1A)
    public static let errorDark = Color(hex: 0xFFB4AB)
}
