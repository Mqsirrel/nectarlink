import SwiftUI
import UIKit

/// Full-screen OLED Desk / Standby companion display with automatic pixel-shift burn-in protection.
struct DeskScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme
    let onExit: () -> Void

    @State private var now = Date()
    @State private var pixelShift = CGSize.zero

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let shiftTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    if let pc = store.activePc {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(pc.link.isConnected ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                            Text("\(pc.info.name) • \(pc.link.badgeText)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    }

                    Spacer()

                    Button(action: onExit) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Large Ambient Clock
                VStack(spacing: 4) {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary)

                    Text(now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                // Active PC Media Card
                if let pc = store.activePc,
                   let player = store.state.media[pc.id]?.first {
                    let artData = player.art ?? player.artKey.flatMap { store.state.mediaArt[$0] }
                    HStack(spacing: 14) {
                        if let artData, let img = UIImage(data: artData) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(palette.primary)
                                .frame(width: 58, height: 58)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(player.title ?? player.app)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let artist = player.artist {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()

                        HStack(spacing: 16) {
                            Button {
                                store.mediaCommand(deviceId: pc.id, player: player.id, action: .previous)
                            } label: {
                                Image(systemName: "backward.fill")
                            }

                            Button {
                                store.mediaCommand(
                                    deviceId: pc.id,
                                    player: player.id,
                                    action: player.playing ? .pause : .play
                                )
                            } label: {
                                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.largeTitle)
                            }

                            Button {
                                store.mediaCommand(deviceId: pc.id, player: player.id, action: .next)
                            } label: {
                                Image(systemName: "forward.fill")
                            }
                        }
                        .foregroundStyle(palette.primary)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
                }

                // 2x2 Quick Actions
                if let pc = store.activePc {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        deskTile(icon: "lock.fill", title: "Lock PC") {
                            store.lockPc(id: pc.id)
                        }
                        deskTile(icon: "moon.zzz.fill", title: "Sleep PC") {
                            store.sleepPc(id: pc.id)
                        }
                        deskTile(icon: "speaker.slash.fill", title: "Mute PC") {
                            let muted = store.state.deckStates[pc.id]?.muted ?? false
                            store.setPcAudio(id: pc.id, volume: nil, muted: !muted)
                        }
                        deskTile(icon: "doc.on.clipboard", title: "Send Clipboard") {
                            store.sendCurrentClipboard(to: pc.id)
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .offset(pixelShift)
        }
        .statusBarHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(clockTimer) { date in
            now = date
        }
        .onReceive(shiftTimer) { _ in
            withAnimation(.easeInOut(duration: 1.5)) {
                pixelShift = CGSize(
                    width: CGFloat.random(in: -6...6),
                    height: CGFloat.random(in: -8...8)
                )
            }
        }
    }

    private func deskTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(palette.primary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
