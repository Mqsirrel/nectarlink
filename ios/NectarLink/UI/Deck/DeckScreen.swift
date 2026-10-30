import SwiftUI
import UIKit

struct DeckScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme

    @State private var selectedPageIndex = 0
    @State private var volumeDraft: Double = 60
    @State private var isDraggingVolume = false

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    private var defaultPages: [DeckPage] {
        [
            DeckPage(
                id: "default",
                name: "Quick Controls",
                tiles: [
                    DeckTile(id: "media.play_pause", label: "Play / Pause", icon: "play", color: "#FFB95F", kind: "media"),
                    DeckTile(id: "media.prev", label: "Previous", icon: "skip_prev", color: "#68A0F8", kind: "media"),
                    DeckTile(id: "media.next", label: "Next Track", icon: "skip_next", color: "#68A0F8", kind: "media"),
                    DeckTile(id: "audio.mute", label: "Mute PC", icon: "volume_off", color: "#F28B82", kind: "audio"),
                    DeckTile(id: "audio.mic_mute", label: "Mute PC Mic", icon: "mic_off", color: "#F28B82", kind: "audio"),
                    DeckTile(id: "pc.screenshot", label: "PC Screenshot", icon: "screenshot", color: "#81C995", kind: "system"),
                    DeckTile(id: "pc.lock", label: "Lock PC", icon: "lock", color: "#FDD663", kind: "system"),
                    DeckTile(id: "pc.sleep", label: "Sleep PC", icon: "sleep", color: "#C58AF9", kind: "system"),
                    DeckTile(id: "slide.next", label: "Next Slide", icon: "arrow_right", color: "#FFB95F", kind: "slide")
                ]
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.surface.ignoresSafeArea()
                if theme.family == .hive {
                    HiveCombView(
                        palette: palette,
                        isDark: theme.isDark(systemScheme: systemScheme),
                        isConnected: store.activePc?.link.isConnected ?? false
                    )
                }

                ScrollView {
                    VStack(spacing: 16) {
                        if let pc = store.activePc {
                            let deckState = store.state.deckStates[pc.id]
                            pcAudioCard(pc: pc, deckState: deckState)

                            let pages = store.state.deckLayouts[pc.id]?.pages.isEmpty == false
                                ? store.state.deckLayouts[pc.id]!.pages
                                : defaultPages
                            let safeIndex = min(selectedPageIndex, max(0, pages.count - 1))

                            if pages.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(pages.enumerated()), id: \.element.id) { idx, page in
                                            Button {
                                                selectedPageIndex = idx
                                            } label: {
                                                Text(page.name)
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        safeIndex == idx ? palette.primary : palette.surfaceContainerHigh,
                                                        in: Capsule()
                                                    )
                                                    .foregroundStyle(
                                                        safeIndex == idx ? palette.onPrimary : palette.onSurface
                                                    )
                                            }
                                        }
                                    }
                                }
                            }

                            let tiles = pages[safeIndex].tiles
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(tiles, id: \.id) { tile in
                                    deckTileButton(tile: tile, deckState: deckState)
                                }
                            }
                        } else {
                            Text("Pair and connect a PC to use Stream Deck controls.")
                                .font(.subheadline)
                                .foregroundStyle(palette.onSurfaceVariant)
                                .padding(32)
                                .frame(maxWidth: .infinity)
                                .nectarCard(palette: palette, family: theme.family)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle(store.activePc.map { "Deck • \($0.info.name)" } ?? "Stream Deck")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pcAudioCard(pc: PairedDevice, deckState: DeckState?) -> some View {
        let muted = deckState?.muted ?? false
        let currentVol = Double(deckState?.volume ?? UInt8(volumeDraft))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PC Master Volume", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Text("\(Int(isDraggingVolume ? volumeDraft : currentVol))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(palette.primary)
            }

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.setPcAudio(id: pc.id, volume: nil, muted: !muted)
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(
                            muted ? Tokens.errorDark.opacity(0.25) : palette.surfaceContainerHigh,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(palette.onSurface)
                }

                Slider(
                    value: Binding(
                        get: { isDraggingVolume ? volumeDraft : currentVol },
                        set: { newVal in
                            volumeDraft = newVal
                            store.setPcAudio(id: pc.id, volume: UInt8(newVal.rounded()), muted: false)
                        }
                    ),
                    in: 0...100,
                    onEditingChanged: { editing in
                        isDraggingVolume = editing
                    }
                )
                .tint(palette.primary)
            }
        }
        .padding(16)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 20)
    }

    private func deckTileButton(tile: DeckTile, deckState: DeckState?) -> some View {
        let accentColor = parseHexColor(tile.color) ?? palette.primary
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            store.deckPress(tileId: tile.id)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: sfSymbol(for: tile.icon, deckState: deckState))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 48, height: 48)
                    .background(accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(tile.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .padding(10)
            .nectarCard(palette: palette, family: theme.family, cornerRadius: 20)
        }
    }

    private func sfSymbol(for icon: String, deckState: DeckState?) -> String {
        switch icon.lowercased() {
        case "play", "play_pause":
            return (deckState?.playing == true) ? "pause.fill" : "play.fill"
        case "skip_prev", "previous":
            return "backward.fill"
        case "skip_next", "next":
            return "forward.fill"
        case "volume_off", "mute":
            return (deckState?.muted == true) ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case "mic_off", "mic":
            return (deckState?.micMuted == true) ? "mic.slash.fill" : "mic.fill"
        case "screenshot", "camera":
            return "camera.viewfinder"
        case "lock":
            return "lock.fill"
        case "sleep", "moon":
            return "moon.zzz.fill"
        case "arrow_right":
            return "arrow.right.circle.fill"
        case "arrow_left":
            return "arrow.left.circle.fill"
        case "terminal", "code":
            return "terminal.fill"
        case "browser", "web", "globe":
            return "globe"
        default:
            return "square.grid.2x2.fill"
        }
    }

    private func parseHexColor(_ hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let val = UInt32(cleaned, radix: 16) else { return nil }
        return Color(hex: val)
    }
}
