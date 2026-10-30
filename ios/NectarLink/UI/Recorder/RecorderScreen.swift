import AVFoundation
import SwiftUI
import UIKit

struct RecorderScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @ObservedObject private var recorder = VoiceRecorder.shared
    @ObservedObject private var micStreamer = MicStreamer.shared
    @Environment(\.colorScheme) private var systemScheme

    @State private var markerNote = ""

    private var palette: Palette {
        theme.palette(for: systemScheme)
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
                    VStack(spacing: 18) {
                        wirelessMicCard
                        voiceRecorderCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Audio & Voice")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Wireless PC Microphone Card

    private var wirelessMicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: micStreamer.isStreaming ? "mic.badge.plus" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(micStreamer.isStreaming ? palette.onPrimary : palette.primary)
                    .frame(width: 46, height: 46)
                    .background(
                        micStreamer.isStreaming ? palette.primary : palette.primaryContainer.opacity(0.38),
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Wireless PC Microphone")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.onSurface)
                    Text(
                        micStreamer.isStreaming
                            ? "Streaming 48 kHz PCM audio to PC"
                            : "Use your iPhone microphone as a live input on your PC"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer()
            }

            if let pc = store.activePc {
                Button {
                    Task {
                        if micStreamer.isStreaming {
                            micStreamer.stop()
                            if let node = store.node {
                                try? await node.micStop(pcId: pc.id)
                            }
                        } else {
                            let granted = await MicStreamer.requestPermission()
                            guard granted else {
                                store.showToast("Microphone permission required")
                                return
                            }
                            _ = micStreamer.start(pcId: pc.id)
                        }
                    }
                } label: {
                    Label(
                        micStreamer.isStreaming ? "Stop Microphone Stream" : "Stream Mic to \(pc.info.name)",
                        systemImage: micStreamer.isStreaming ? "stop.fill" : "waveform"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        micStreamer.isStreaming ? Tokens.errorDark : palette.primary,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(micStreamer.isStreaming ? Color.black : palette.onPrimary)
                }
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    // MARK: - Voice Note Recorder Card

    private var voiceRecorderCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Voice Recorder", systemImage: "recordingtape")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                if recorder.isRecording {
                    Text(recorder.isPaused ? "PAUSED" : "RECORDING")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Tokens.errorDark.opacity(0.25), in: Capsule())
                        .foregroundStyle(palette.onSurface)
                }
            }

            Text(formatDuration(ms: recorder.elapsedMs))
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.onSurface)
                .padding(.vertical, 6)

            // Live amplitude meter bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.surfaceContainerHigh)
                    Capsule()
                        .fill(palette.primary)
                        .frame(width: max(8, geo.size.width * CGFloat(recorder.amplitude)))
                        .animation(.easeOut(duration: 0.08), value: recorder.amplitude)
                }
            }
            .frame(height: 12)

            if recorder.isRecording {
                HStack(spacing: 8) {
                    TextField("Bookmark label (optional)…", text: $markerNote)
                        .padding(10)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(palette.onSurface)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        recorder.addMarker(label: markerNote)
                        markerNote = ""
                    } label: {
                        Label("Flag", systemImage: "flag.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(palette.secondaryContainer, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(palette.onSecondaryContainer)
                    }
                }

                if !recorder.markers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(recorder.markers.enumerated()), id: \.offset) { _, m in
                            HStack {
                                Image(systemName: "flag.fill")
                                    .font(.caption2)
                                    .foregroundStyle(palette.primary)
                                Text(m.label ?? "Marker")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(palette.onSurface)
                                Spacer()
                                Text(formatDuration(ms: m.atMs))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                    }
                    .padding(10)
                    .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            // Record / Pause / Send Controls
            HStack(spacing: 12) {
                if !recorder.isRecording {
                    Button {
                        Task {
                            let granted = await MicStreamer.requestPermission()
                            guard granted else {
                                store.showToast("Microphone permission required")
                                return
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            _ = recorder.start()
                        }
                    } label: {
                        Label("Start Recording", systemImage: "record.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(palette.primary, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(palette.onPrimary)
                    }
                } else {
                    Button {
                        recorder.discard()
                    } label: {
                        Image(systemName: "trash.fill")
                            .frame(width: 48, height: 48)
                            .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(palette.onSurface)
                    }

                    Button {
                        if recorder.isPaused {
                            recorder.resume()
                        } else {
                            recorder.pause()
                        }
                    } label: {
                        Label(
                            recorder.isPaused ? "Resume" : "Pause",
                            systemImage: recorder.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(palette.onSurface)
                    }

                    Button {
                        guard let finished = recorder.stop() else { return }
                        if let pc = store.activePc {
                            store.sendRecording(
                                to: pc.id,
                                fileUrl: finished.url,
                                markers: finished.markers
                            )
                        } else {
                            store.showToast("Saved recording locally")
                        }
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(palette.primary, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(palette.onPrimary)
                    }
                }
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    private func formatDuration(ms: UInt64) -> String {
        let totalTenths = ms / 100
        let tenths = totalTenths % 10
        let totalSeconds = totalTenths / 10
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60
        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }
}
