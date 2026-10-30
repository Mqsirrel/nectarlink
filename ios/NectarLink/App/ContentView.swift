import SwiftUI

struct ContentView: View {
    @ObservedObject var store = CoreStore.shared
    @ObservedObject var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme

    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case remote = "Remote"
        case deck = "Deck"
        case webcam = "Webcam"
        case audio = "Audio"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .remote: return "hand.point.up.left.fill"
            case .deck: return "square.grid.2x2.fill"
            case .webcam: return "video.fill"
            case .audio: return "waveform"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @State private var selectedTab: Tab = .home
    @State private var showWalkthrough = !UserDefaults.standard.bool(forKey: "nectarlink.walkthrough.done")
    @State private var showPairing = false
    @State private var showDeskMode = false
    @State private var pcMirrorTarget: (pcId: String, watchPlayer: String?)?

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if showWalkthrough {
                WalkthroughScreen(
                    store: store,
                    theme: theme,
                    onFinish: {
                        withAnimation { showWalkthrough = false }
                    },
                    onOpenPairing: {
                        showWalkthrough = false
                        showPairing = true
                    }
                )
            } else {
                Group {
                    switch selectedTab {
                    case .home:
                        HomeScreen(
                            store: store,
                            theme: theme,
                            onOpenPairing: { showPairing = true },
                            onOpenDeskMode: { showDeskMode = true },
                            onOpenPcMirror: { pcId, player in
                                pcMirrorTarget = (pcId, player)
                            }
                        )
                    case .remote:
                        RemoteScreen(store: store, theme: theme)
                    case .deck:
                        DeckScreen(store: store, theme: theme)
                    case .webcam:
                        WebcamScreen(store: store, theme: theme)
                    case .audio:
                        RecorderScreen(store: store, theme: theme)
                    case .settings:
                        SettingsScreen(store: store, theme: theme)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                floatingTabBar
            }

            if let toast = store.toastMessage {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(palette.primary, in: Capsule())
                    .foregroundStyle(palette.onPrimary)
                    .shadow(radius: 6)
                    .padding(.bottom, 86)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
        .sheet(isPresented: $showPairing) {
            PairingScreen(store: store, theme: theme)
        }
        .fullScreenCover(isPresented: $showDeskMode) {
            DeskScreen(store: store, theme: theme) {
                showDeskMode = false
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { pcMirrorTarget != nil },
                set: { if !$0 { pcMirrorTarget = nil } }
            )
        ) {
            if let target = pcMirrorTarget {
                PcMirrorView(
                    store: store,
                    pcId: target.pcId,
                    watchPlayer: target.watchPlayer
                ) {
                    pcMirrorTarget = nil
                }
            }
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        isSelected ? palette.primary : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(isSelected ? palette.onPrimary : palette.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(palette.outlineVariant.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
