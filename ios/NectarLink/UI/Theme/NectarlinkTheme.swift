import Combine
import CoreGraphics
import SwiftUI
import UIKit

enum ThemeFamily: String, CaseIterable, Identifiable {
    case hive = "hive"
    case bloom = "bloom"
    case glass = "glass"
    case graphite = "graphite"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hive: return "Hive"
        case .bloom: return "Bloom"
        case .glass: return "Liquid Glass"
        case .graphite: return "Graphite"
        }
    }

    var subtitle: String {
        switch self {
        case .hive: return "Warm honeycomb & amber glow"
        case .bloom: return "Expressive Material seed palettes"
        case .glass: return "Translucent frosted surfaces"
        case .graphite: return "Crisp e-ink paper & slate"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case amoled = "amoled"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .amoled: return "AMOLED"
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var family: ThemeFamily {
        didSet { UserDefaults.standard.set(family.rawValue, forKey: "nectarlink.theme.family") }
    }

    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "nectarlink.theme.appearance") }
    }

    @Published var bloomSeedName: String {
        didSet { UserDefaults.standard.set(bloomSeedName, forKey: "nectarlink.theme.seed") }
    }

    @Published var useArtworkColors: Bool {
        didSet { UserDefaults.standard.set(useArtworkColors, forKey: "nectarlink.theme.artwork") }
    }

    @Published private(set) var artworkPalettes: (light: Palette, dark: Palette)?

    private init() {
        let rawFamily = UserDefaults.standard.string(forKey: "nectarlink.theme.family") ?? ThemeFamily.hive.rawValue
        self.family = ThemeFamily(rawValue: rawFamily) ?? .hive

        let rawAppearance = UserDefaults.standard.string(forKey: "nectarlink.theme.appearance") ?? AppearanceMode.dark.rawValue
        self.appearance = AppearanceMode(rawValue: rawAppearance) ?? .dark

        self.bloomSeedName = UserDefaults.standard.string(forKey: "nectarlink.theme.seed") ?? Tokens.defaultSeed
        self.useArtworkColors = UserDefaults.standard.object(forKey: "nectarlink.theme.artwork") as? Bool ?? true
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark, .amoled: return .dark
        }
    }

    func isDark(systemScheme: ColorScheme) -> Bool {
        switch appearance {
        case .system: return systemScheme == .dark
        case .light: return false
        case .dark, .amoled: return true
        }
    }

    func palette(for systemScheme: ColorScheme) -> Palette {
        let dark = isDark(systemScheme: systemScheme)
        let base: Palette

        if useArtworkColors, let art = artworkPalettes {
            base = dark ? art.dark : art.light
        } else {
            switch family {
            case .hive:
                base = dark ? Tokens.hiveComb : Tokens.hiveWax
            case .bloom, .glass:
                let seed = Tokens.bloomSeeds[bloomSeedName] ?? Tokens.bloomSeeds[Tokens.defaultSeed]!
                base = dark ? seed.dark : seed.light
            case .graphite:
                base = dark ? Tokens.graphiteSlate : Tokens.graphitePaper
            }
        }

        if appearance == .amoled && dark {
            return Palette(
                primary: base.primary,
                onPrimary: base.onPrimary,
                primaryContainer: base.primaryContainer,
                onPrimaryContainer: base.onPrimaryContainer,
                secondaryContainer: base.secondaryContainer,
                onSecondaryContainer: base.onSecondaryContainer,
                surface: Color(hex: 0x000000),
                surfaceContainerLow: Color(hex: 0x050507),
                surfaceContainer: Color(hex: 0x0B0B0E),
                surfaceContainerHigh: Color(hex: 0x131317),
                surfaceContainerHighest: Color(hex: 0x1B1B20),
                onSurface: base.onSurface,
                onSurfaceVariant: base.onSurfaceVariant,
                outline: base.outline,
                outlineVariant: base.outlineVariant
            )
        }
        return base
    }

    func updateArtwork(jpegOrPng: Data?, cacheKey: String?) {
        guard useArtworkColors, let data = jpegOrPng, let image = UIImage(data: data) else {
            artworkPalettes = nil
            return
        }
        Task.detached(priority: .utility) {
            guard let (rgba, w, h) = Self.downsampleToRgba(image: image, maxSide: 64),
                  let scheme = extractArtworkScheme(rgba: rgba, width: w, height: h, cacheKey: cacheKey) else {
                await MainActor.run { self.artworkPalettes = nil }
                return
            }
            let light = Self.toPalette(scheme.light)
            let dark = Self.toPalette(scheme.dark)
            await MainActor.run {
                self.artworkPalettes = (light: light, dark: dark)
            }
        }
    }

    nonisolated private static func toPalette(_ p: FfiRolePalette) -> Palette {
        Palette(
            primary: Color(hex: p.primary),
            onPrimary: Color(hex: p.onPrimary),
            primaryContainer: Color(hex: p.primaryContainer),
            onPrimaryContainer: Color(hex: p.onPrimaryContainer),
            secondaryContainer: Color(hex: p.secondaryContainer),
            onSecondaryContainer: Color(hex: p.onSecondaryContainer),
            surface: Color(hex: p.surface),
            surfaceContainerLow: Color(hex: p.surfaceContainerLow),
            surfaceContainer: Color(hex: p.surfaceContainer),
            surfaceContainerHigh: Color(hex: p.surfaceContainerHigh),
            surfaceContainerHighest: Color(hex: p.surfaceContainerHighest),
            onSurface: Color(hex: p.onSurface),
            onSurfaceVariant: Color(hex: p.onSurfaceVariant),
            outline: Color(hex: p.outline),
            outlineVariant: Color(hex: p.outlineVariant)
        )
    }

    nonisolated private static func downsampleToRgba(image: UIImage, maxSide: Int) -> (Data, UInt32, UInt32)? {
        guard let cgImage = image.cgImage else { return nil }
        let w = min(maxSide, max(1, cgImage.width))
        let h = min(maxSide, max(1, cgImage.height))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (Data(bytes), UInt32(w), UInt32(h))
    }
}
