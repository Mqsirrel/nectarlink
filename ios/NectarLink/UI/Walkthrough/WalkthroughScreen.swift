import AVFoundation
import Contacts
import Photos
import SwiftUI
import UserNotifications

struct WalkthroughScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme

    let onFinish: () -> Void
    let onOpenPairing: () -> Void

    @State private var step = 0
    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var photosGranted = {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }()
    @State private var contactsGranted = CNContactStore.authorizationStatus(for: .contacts) == .authorized

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    var body: some View {
        ZStack {
            palette.surface.ignoresSafeArea()
            if theme.family == .hive {
                HiveCombView(
                    palette: palette,
                    isDark: theme.isDark(systemScheme: systemScheme),
                    isConnected: true
                )
            }

            VStack(spacing: 20) {
                HStack {
                    Text("NectarLink")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(palette.primary)
                    Spacer()
                    Button("Skip") {
                        completeWalkthrough()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $step) {
                    welcomePage.tag(0)
                    permissionsPage.tag(1)
                    capabilitiesPage.tag(2)
                    readyPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack(spacing: 12) {
                    if step > 0 {
                        Button {
                            withAnimation { step -= 1 }
                        } label: {
                            Text("Back")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(palette.onSurface)
                                .nectarCard(palette: palette, family: theme.family, cornerRadius: 14)
                        }
                    }

                    Button {
                        if step < 3 {
                            withAnimation { step += 1 }
                        } else {
                            completeWalkthrough()
                        }
                    } label: {
                        Text(step < 3 ? "Continue" : "Get Started")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(palette.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(palette.onPrimary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(palette.primary)
                .padding(24)
                .background(palette.primaryContainer.opacity(0.35), in: Circle())

            Text("Your iPhone & PC, Properly Connected")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.onSurface)

            Text("Direct, end-to-end encrypted QUIC connections over Wi-Fi or Away relay. No accounts, no cloud servers, and zero telemetry.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var permissionsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("iOS Permissions")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.onSurface)

                Text("Grant only what you want to use. You can change any of these later in iOS Settings.")
                    .font(.subheadline)
                    .foregroundStyle(palette.onSurfaceVariant)

                permissionRow(
                    icon: "photo.on.rectangle.angled",
                    title: "Photo Library",
                    subtitle: "Browse recent photos & screenshots on your PC",
                    granted: photosGranted
                ) {
                    Task {
                        photosGranted = await IosPhotos.requestPermission()
                        store.refresh()
                    }
                }

                permissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "Use iPhone as a 4K PC webcam, Continuity Camera & QR scanner",
                    granted: cameraGranted
                ) {
                    Task {
                        cameraGranted = await WebcamStreamer.requestPermission()
                        store.refresh()
                    }
                }

                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Use iPhone as a wireless PC mic & record voice notes",
                    granted: micGranted
                ) {
                    Task {
                        micGranted = await MicStreamer.requestPermission()
                        store.refresh()
                    }
                }

                permissionRow(
                    icon: "person.crop.circle",
                    title: "Contacts",
                    subtitle: "Match caller names & search contacts from your PC",
                    granted: contactsGranted
                ) {
                    Task {
                        contactsGranted = await IosContacts.requestPermission()
                        store.refresh()
                    }
                }
            }
            .padding(24)
        }
    }

    private var capabilitiesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Built for iPhone")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.onSurface)

                Text("Everything that runs natively on iOS:")
                    .font(.subheadline)
                    .foregroundStyle(palette.onSurfaceVariant)

                capabilityBadge("arrow.up.doc.fill", "Files, Photos & System Share Sheet", "Send files, photos, or links from any app via the NectarLink Share Extension.")
                capabilityBadge("video.fill", "Hardware H.264 / HEVC Webcam & Screen Mirror", "Stream your iPhone camera or ReplayKit screen to your PC, or view your PC screen on iPhone.")
                capabilityBadge("hand.point.up.left.fill", "Trackpad, Air Mouse, Laser & Stream Deck", "Control your PC cursor, keyboard, presentations, and custom macro tiles.")
                capabilityBadge("doc.viewfinder", "Continuity Camera & Document Scanner", "Snap photos or perspective-corrected scans right into your PC.")
            }
            .padding(24)
        }
    }

    private var readyPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(palette.primary)
                .padding(24)
                .background(palette.primaryContainer.opacity(0.35), in: Circle())

            Text("Ready to Pair")
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.onSurface)

            Text("Open NectarLink on your Windows, macOS, or Linux PC and scan its QR code—or select your PC from the Nearby list.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 24)

            Button {
                completeWalkthrough()
                onOpenPairing()
            } label: {
                Label("Pair with a PC Now", systemImage: "qrcode")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(palette.secondaryContainer, in: Capsule())
                    .foregroundStyle(palette.onSecondaryContainer)
            }
            Spacer()
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(palette.primary)
                .frame(width: 36, height: 36)
                .background(palette.primaryContainer.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onSurface)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.primary)
                    .font(.title3)
            } else {
                Button("Allow", action: action)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.primary, in: Capsule())
                    .foregroundStyle(palette.onPrimary)
            }
        }
        .padding(14)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 16)
    }

    private func capabilityBadge(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(palette.primary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onSurface)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer()
        }
        .padding(14)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 16)
    }

    private func completeWalkthrough() {
        UserDefaults.standard.set(true, forKey: "nectarlink.walkthrough.done")
        onFinish()
    }
}
