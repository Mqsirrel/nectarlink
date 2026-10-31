import AVFoundation
import SwiftUI

struct PairingScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dismiss) private var dismiss

    enum PairingMode: String, CaseIterable, Identifiable {
        case scan = "Scan QR"
        case nearby = "Nearby"
        case myQr = "My QR"
        var id: String { rawValue }
    }

    @State private var mode: PairingMode = .scan
    @State private var manualLink = ""
    @State private var hasCameraPermission = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

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
                        isConnected: false
                    )
                }

                VStack(spacing: 16) {
                    Picker("Pairing Mode", selection: $mode) {
                        ForEach(PairingMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    if let error = store.state.pairingError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error.message)
                                .font(.caption)
                            Spacer()
                            Button {
                                store.state.pairingError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                        .padding(12)
                        .background(Tokens.errorDark.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(palette.onSurface)
                        .padding(.horizontal, 20)
                    }

                    switch mode {
                    case .scan:
                        scanTab
                    case .nearby:
                        nearbyTab
                    case .myQr:
                        myQrTab
                    }

                    Spacer()
                }
                .padding(.top, 8)

                if let prompt = store.state.pairingPrompt {
                    sasPromptOverlay(prompt)
                }
            }
            .navigationTitle("Pair Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        store.cancelPairing()
                        dismiss()
                    }
                }
            }
            .onChange(of: mode) { newMode in
                if newMode == .myQr && store.state.myQrLink == nil {
                    store.startQrPairing()
                }
            }
            .onChange(of: store.state.paired.count) { _ in
                if !store.state.pairingBusy && store.state.pairingPrompt == nil {
                    dismiss()
                }
            }
        }
    }

    private var scanTab: some View {
        VStack(spacing: 16) {
            if hasCameraPermission {
                ZStack {
                    QrScannerView { scannedUri in
                        store.joinPairing(link: scannedUri)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(palette.primary, lineWidth: 2)
                    )

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                        .frame(width: 210, height: 210)
                }
                .frame(height: 290)
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(palette.primary)
                    Text("Camera access is needed to scan the PC QR code.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.onSurfaceVariant)
                    Button("Grant Camera Access") {
                        Task {
                            hasCameraPermission = await WebcamStreamer.requestPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .nectarCard(palette: palette, family: theme.family)
                .padding(.horizontal, 20)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Or paste pairing link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                HStack(spacing: 8) {
                    TextField("nectarlink://pair?...", text: $manualLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(palette.onSurface)

                    Button("Join") {
                        let trimmed = manualLink.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.joinPairing(link: trimmed)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(palette.primary, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(palette.onPrimary)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var nearbyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovered on Wi-Fi")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .tint(palette.primary)
            }
            .padding(.horizontal, 20)

            if store.state.discovered.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(palette.primary)
                    Text("Looking for PCs with NectarLink open on the same network…")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .nectarCard(palette: palette, family: theme.family)
                .padding(.horizontal, 20)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.state.discovered, id: \.id) { peer in
                            HStack(spacing: 14) {
                                Image(systemName: "desktopcomputer")
                                    .font(.title2)
                                    .foregroundStyle(palette.primary)
                                    .frame(width: 40, height: 40)
                                    .background(palette.primaryContainer.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.name ?? "NectarLink PC")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.onSurface)
                                    Text(String(peer.id.prefix(8)))
                                        .font(.caption)
                                        .foregroundStyle(palette.onSurfaceVariant)
                                }
                                Spacer()
                                Button("Pair") {
                                    store.startNearbyPairing(peerId: peer.id)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(palette.primary, in: Capsule())
                                .foregroundStyle(palette.onPrimary)
                            }
                            .padding(14)
                            .nectarCard(palette: palette, family: theme.family, cornerRadius: 16)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var myQrTab: some View {
        VStack(spacing: 18) {
            if let qrLink = store.state.myQrLink,
               let image = QrCodeImageGenerator.generate(from: qrLink, size: 240) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(radius: 8)

                Text("Scan this QR code from another NectarLink device")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.onSurfaceVariant)

                Button {
                    UIPasteboard.general.string = qrLink
                    store.showToast("Copied pairing link")
                } label: {
                    Label("Copy Pairing Link", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(palette.secondaryContainer, in: Capsule())
                        .foregroundStyle(palette.onSecondaryContainer)
                }
            } else {
                ProgressView("Generating pairing code…")
                    .tint(palette.primary)
                    .padding(40)
            }
        }
        .padding(24)
    }

    private func sasPromptOverlay(_ prompt: PairingPrompt) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(palette.primary)

                Text("Confirm Pairing Code")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.onSurface)

                Text("Check that **\(prompt.peer.name)** shows this exact 6-digit verification code:")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.onSurfaceVariant)

                Text(prompt.code)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .kerning(4)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(palette.primaryContainer, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(palette.onPrimaryContainer)

                HStack(spacing: 12) {
                    Button {
                        store.confirmPairing(match: false)
                    } label: {
                        Text("Reject")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(palette.onSurface)
                    }

                    Button {
                        store.confirmPairing(match: true)
                    } label: {
                        Text("Codes Match")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(palette.primary, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(palette.onPrimary)
                    }
                }
            }
            .padding(24)
            .nectarCard(palette: palette, family: theme.family, cornerRadius: 24)
            .padding(.horizontal, 28)
        }
    }
}
