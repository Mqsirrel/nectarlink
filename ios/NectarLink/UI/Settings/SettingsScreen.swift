import SwiftUI
import UIKit

struct SettingsScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme

    @State private var probeHost = ""
    @State private var showClearConfirm = false

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    private let iosVisibleToggles: [(id: String, label: String, icon: String)] = [
        ("files", "File Transfers", "folder.fill"),
        ("clipboard", "Clipboard Sync", "doc.on.clipboard"),
        ("photos", "Photos & Continuity Camera", "photo.on.rectangle"),
        ("contacts", "Contacts Lookup", "person.crop.circle"),
        ("calls", "Call State & Dialer", "phone.fill"),
        ("media", "Media Controls", "music.note"),
        ("mirroring", "Screen Mirroring (ReplayKit)", "rectangle.on.rectangle"),
        ("webcam", "iPhone as PC Webcam", "video.fill"),
        ("mic", "iPhone as PC Microphone", "mic.fill"),
        ("storage", "Phone File Storage", "externaldrive.fill"),
        ("pc_actions", "PC Power & Audio Actions", "power"),
        ("toggles", "Quick Settings (Torch/Volume/Brightness)", "slider.horizontal.3"),
        ("remote_files", "Browse PC Files in Away Mode", "network")
    ]

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
                        appearanceSection
                        pairedDevicesSection
                        networkAndLocalSendSection
                        iosPermissionsSection
                        privacyAndRetentionSection
                        aboutSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Clear All Local History?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear History", role: .destructive) {
                    store.clearAllLocalData()
                }
            } message: {
                Text("This removes local clipboard history and timeline activity while keeping your paired PCs and encryption identity intact.")
            }
        }
    }

    // MARK: - Appearance & Theme Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance & Theme")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.onSurface)

            Picker("Theme Family", selection: $theme.family) {
                ForEach(ThemeFamily.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Appearance", selection: $theme.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if theme.family == .bloom || theme.family == .glass {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Seed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.onSurfaceVariant)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Tokens.bloomSeeds.keys.sorted(), id: \.self) { key in
                                if let seed = Tokens.bloomSeeds[key] {
                                    let selected = theme.bloomSeedName == key
                                    Button {
                                        theme.bloomSeedName = key
                                        if let node = store.node {
                                            Task { await node.updateAccent(accent: seed.seedRgb) }
                                        }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Circle()
                                                .fill(seed.color)
                                                .frame(width: 34, height: 34)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(
                                                            selected ? palette.onSurface : Color.clear,
                                                            lineWidth: 2.5
                                                        )
                                                )
                                            Text(key.capitalized)
                                                .font(.caption2)
                                                .foregroundStyle(palette.onSurfaceVariant)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Toggle("Dynamic Album Artwork Colours", isOn: $theme.useArtworkColors)
                .font(.subheadline)
                .foregroundStyle(palette.onSurface)
                .tint(palette.primary)
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    // MARK: - Paired Devices & Per-Device Feature Toggles

    private var pairedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paired Devices")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.onSurface)

            if store.state.paired.isEmpty {
                Text("No paired PCs.")
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
            } else {
                ForEach(store.state.paired, id: \.id) { pc in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(
                                "Auto-Reconnect",
                                isOn: Binding(
                                    get: { pc.reconnect },
                                    set: { store.setReconnect(deviceId: pc.id, on: $0) }
                                )
                            )
                            .font(.subheadline.weight(.medium))
                            .tint(palette.primary)

                            Divider()

                            ForEach(iosVisibleToggles, id: \.id) { item in
                                let isOn = store.state.deviceToggles[pc.id]?[item.id] ?? true
                                Toggle(
                                    isOn: Binding(
                                        get: { isOn },
                                        set: { store.setDeviceToggle(deviceId: pc.id, name: item.id, enabled: $0) }
                                    )
                                ) {
                                    Label(item.label, systemImage: item.icon)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(palette.onSurface)
                                }
                                .tint(palette.primary)
                            }

                            Divider()

                            Button(role: .destructive) {
                                store.unpair(id: pc.id)
                            } label: {
                                Label("Unpair \(pc.info.name)", systemImage: "trash")
                                    .font(.caption.weight(.bold))
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pc.info.kind == .laptop ? "laptopcomputer" : "desktopcomputer")
                                .foregroundStyle(palette.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pc.info.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.onSurface)
                                Text(pc.link.badgeText)
                                    .font(.caption2)
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                    }
                    .padding(12)
                    .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    // MARK: - Networking & LocalSend Section

    private var networkAndLocalSendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connectivity & LocalSend")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.onSurface)

            Toggle(
                isOn: Binding(
                    get: { store.state.awayMode },
                    set: { store.setAwayMode($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Away Mode (Relay & Mobile Data)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.onSurface)
                    Text("Stay connected to your PC when away from home Wi-Fi")
                        .font(.caption)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
            .tint(palette.primary)

            Divider()

            Toggle(
                isOn: Binding(
                    get: { store.state.localSendEnabled },
                    set: { store.setLocalSendEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LocalSend v2.1 Compatibility")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.onSurface)
                    Text("Discover and exchange files with LocalSend devices on LAN (port 53317)")
                        .font(.caption)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
            .tint(palette.primary)

            if store.state.localSendEnabled {
                HStack(spacing: 8) {
                    TextField("Probe IP (e.g. 192.168.1.42)", text: $probeHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(palette.onSurface)

                    Button("Probe") {
                        let trimmed = probeHost.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.probeLocalSendPeer(host: trimmed)
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.primary, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(palette.onPrimary)
                }
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    // MARK: - iOS Permissions & Capabilities Note

    private var iosPermissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("iOS Permissions & Sandbox")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.primary)
            }

            Text("NectarLink uses native iOS frameworks for Photos, Camera, Microphone, Contacts, CallKit observer, and ReplayKit screen mirroring. Features that require Android-only OS hooks (third-party notification mirroring, SMS database access, and virtual per-app displays) are marked as unsupported on iPhone.")
                .font(.caption)
                .foregroundStyle(palette.onSurfaceVariant)
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    // MARK: - Privacy & Data Retention

    private var privacyAndRetentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy & Local Data")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.onSurface)

            if let counts = store.state.dataRetention {
                HStack {
                    Text("Encrypted Clipboard Items")
                        .font(.caption)
                        .foregroundStyle(palette.onSurfaceVariant)
                    Spacer()
                    Text("\(counts.clipboardItems)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(palette.onSurface)
                }
                HStack {
                    Text("Timeline Entries")
                        .font(.caption)
                        .foregroundStyle(palette.onSurfaceVariant)
                    Spacer()
                    Text("\(counts.timelineItems) (Retained \(counts.timelineRetentionDays)d)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(palette.onSurface)
                }
            }

            HStack(spacing: 8) {
                ForEach([7, 30, 90], id: \.self) { days in
                    let active = store.state.timelineRetention?.maxDays == UInt32(days)
                    Button("\(days) Days") {
                        store.setTimelineRetention(maxDays: UInt32(days), maxEntries: 500)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(active ? palette.primary : palette.surfaceContainerHigh, in: Capsule())
                    .foregroundStyle(active ? palette.onPrimary : palette.onSurface)
                }
                Spacer()
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption.weight(.bold))
                }
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About NectarLink for iPhone")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.onSurface)

            HStack {
                Text("Device ID")
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Text(store.state.myId.isEmpty ? "Starting…" : String(store.state.myId.prefix(16)) + "…")
                    .font(.caption.monospaced())
                    .foregroundStyle(palette.onSurface)
            }

            HStack {
                Text("Shared Rust Core")
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Text("nectarlink-core + UniFFI Swift")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.primary)
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }
}
