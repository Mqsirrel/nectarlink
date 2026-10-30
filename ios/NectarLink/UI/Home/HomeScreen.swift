import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @ObservedObject private var continuityCamera = ContinuityCameraManager.shared
    @Environment(\.colorScheme) private var systemScheme

    let onOpenPairing: () -> Void
    let onOpenDeskMode: () -> Void
    let onOpenPcMirror: (String, String?) -> Void

    @State private var showFileImporter = false
    @State private var handoffFileImporter = false
    @State private var showClipboardHistory = false
    @State private var showTimeline = false
    @State private var showRemoteFiles = false
    @State private var showLinkPrompt = false
    @State private var linkText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

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
                        isConnected: store.activePc?.link.isConnected ?? false,
                        isTransferring: !store.state.transfers.isEmpty
                    )
                }

                ScrollView {
                    VStack(spacing: 16) {
                        if store.state.ringing {
                            ringingBanner
                        }

                        if let offer = store.state.watchOffer {
                            watchOfferBanner(offer)
                        }

                        if store.state.paired.isEmpty {
                            emptyPairedState
                        } else {
                            deviceSelectorRow

                            if let pc = store.activePc {
                                activePcCard(pc)
                                mediaNowPlayingCard(for: pc)
                                quickSendCard(for: pc)
                                recentPhotosStrip(for: pc)
                            }

                            if !store.state.transfers.isEmpty || !store.state.sendQueue.isEmpty {
                                transfersAndQueueCard
                            }

                            if store.state.localSendEnabled && !store.state.localSendPeers.isEmpty {
                                localSendPeersCard
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    store.refresh()
                }
            }
            .navigationTitle("NectarLink")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showClipboardHistory = true
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }

                    Button {
                        showTimeline = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }

                    Button {
                        onOpenDeskMode()
                    } label: {
                        Image(systemName: "stand.fill")
                    }

                    Button {
                        onOpenPairing()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result, let pc = store.activePc {
                    store.sendFiles(to: pc.id, urls: urls, handoff: handoffFileImporter)
                }
            }
            .sheet(isPresented: $showClipboardHistory) {
                ClipboardHistorySheet(store: store, theme: theme)
            }
            .sheet(isPresented: $showTimeline) {
                TimelineSheet(store: store, theme: theme)
            }
            .sheet(isPresented: $showRemoteFiles) {
                if let pc = store.activePc {
                    RemotePcFilesSheet(store: store, theme: theme, pc: pc)
                }
            }
            .sheet(item: $continuityCamera.activeRequest) { req in
                ContinuityCameraSheet(request: req)
            }
            .alert("Open Link on PC", isPresented: $showLinkPrompt) {
                TextField("https://example.com", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { linkText = "" }
                Button("Open on PC") {
                    if let pc = store.activePc {
                        store.sendLink(to: pc.id, url: linkText)
                    }
                    linkText = ""
                }
            }
            .onChange(of: selectedPhotoItems) { newItems in
                guard !newItems.isEmpty, let pc = store.activePc else { return }
                Task {
                    var stagedUrls: [URL] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("Photo_\(Int(Date().timeIntervalSince1970))_\(stagedUrls.count).\(ext)")
                            if (try? data.write(to: url)) != nil {
                                stagedUrls.append(url)
                            }
                        }
                    }
                    selectedPhotoItems.removeAll()
                    if !stagedUrls.isEmpty {
                        store.sendFiles(to: pc.id, urls: stagedUrls, handoff: false)
                    }
                }
            }
        }
    }

    // MARK: - Banners

    private var ringingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.title2)
                .foregroundStyle(palette.onPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Find My iPhone Alert")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onPrimary)
                Text("Your PC is ringing this iPhone")
                    .font(.caption)
                    .foregroundStyle(palette.onPrimary.opacity(0.85))
            }
            Spacer()
            Button("Stop") {
                store.stopPhoneRinging()
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.surface, in: Capsule())
            .foregroundStyle(palette.primary)
        }
        .padding(16)
        .background(palette.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func watchOfferBanner(_ offer: WatchOfferState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.tv.fill")
                .font(.title2)
                .foregroundStyle(palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue Watching on iPhone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onSurface)
                Text(offer.title ?? offer.player)
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer()
            Button("Watch") {
                store.state.watchOffer = nil
                onOpenPcMirror(offer.fromId, offer.player)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.primary, in: Capsule())
            .foregroundStyle(palette.onPrimary)

            Button {
                store.state.watchOffer = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
            }
        }
        .padding(14)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 18)
    }

    // MARK: - Empty State

    private var emptyPairedState: some View {
        VStack(spacing: 18) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(palette.primary)
                .padding(22)
                .background(palette.primaryContainer.opacity(0.35), in: Circle())

            Text("No Paired PC Yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.onSurface)

            Text("Pair your iPhone with NectarLink on Windows, macOS, or Linux to share files, clipboard, camera, and remote controls.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 16)

            Button {
                onOpenPairing()
            } label: {
                Label("Pair a PC", systemImage: "qrcode.viewfinder")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(palette.primary, in: Capsule())
                    .foregroundStyle(palette.onPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 24)
    }

    // MARK: - Device Selector & Active PC Card

    private var deviceSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.state.paired, id: \.id) { device in
                    let isSelected = store.activePc?.id == device.id
                    Button {
                        store.selectedPcId = device.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(device.link.isConnected ? Color.green : palette.outline)
                                .frame(width: 8, height: 8)
                            Text(device.info.name)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            isSelected ? palette.primaryContainer : palette.surfaceContainerHigh,
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? palette.onPrimaryContainer : palette.onSurface)
                    }
                }
            }
        }
    }

    private func activePcCard(_ pc: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: pc.info.kind == .laptop ? "laptopcomputer" : "desktopcomputer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 52, height: 52)
                    .background(palette.primaryContainer.opacity(0.38), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(pc.info.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(palette.onSurface)
                    HStack(spacing: 8) {
                        Text(pc.link.badgeText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(pc.link.isConnected ? palette.primary : palette.onSurfaceVariant)

                        if let bat = store.state.batteries[pc.id] {
                            Label("\(bat.level)%", systemImage: bat.charging ? "battery.100.bolt" : "battery.75")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                    }
                }
                Spacer()

                if !pc.link.isConnected && pc.canWake {
                    Button {
                        store.wakePc(id: pc.id)
                    } label: {
                        Label("Wake", systemImage: "power")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(palette.primary, in: Capsule())
                            .foregroundStyle(palette.onPrimary)
                    }
                }
            }

            // PC Quick Actions Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickActionPill(
                    icon: "lock.desktopcomputer",
                    label: "Lock PC"
                ) {
                    store.lockPc(id: pc.id)
                }

                quickActionPill(
                    icon: "moon.zzz.fill",
                    label: "Sleep"
                ) {
                    store.sleepPc(id: pc.id)
                }

                let isSpeakerOn = store.state.pcSpeakerPeers.contains(pc.id)
                quickActionPill(
                    icon: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.2",
                    label: isSpeakerOn ? "Speaker On" : "PC Audio",
                    highlighted: isSpeakerOn
                ) {
                    store.togglePcSpeaker(pcId: pc.id)
                }

                quickActionPill(
                    icon: "folder.fill",
                    label: "PC Files"
                ) {
                    showRemoteFiles = true
                }

                quickActionPill(
                    icon: "display",
                    label: "View PC"
                ) {
                    onOpenPcMirror(pc.id, nil)
                }

                quickActionPill(
                    icon: "camera.viewfinder",
                    label: "Snap to PC"
                ) {
                    ContinuityCameraManager.shared.presentManualCapture(pcId: pc.id, mode: "photo")
                }

                quickActionPill(
                    icon: "doc.viewfinder",
                    label: "Scan Doc"
                ) {
                    ContinuityCameraManager.shared.presentManualCapture(pcId: pc.id, mode: "scan")
                }

                let screenMirroring = ScreenMirrorStreamer.shared.isMirroring
                quickActionPill(
                    icon: "rectangle.inset.filled.and.person.filled",
                    label: screenMirroring ? "Stop Cast" : "Cast Screen",
                    highlighted: screenMirroring
                ) {
                    if screenMirroring {
                        ScreenMirrorStreamer.shared.stop(pcId: pc.id)
                    } else {
                        _ = ScreenMirrorStreamer.shared.start(pcId: pc.id, audio: true)
                    }
                }
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    private func quickActionPill(
        icon: String,
        label: String,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                highlighted ? palette.primary : palette.surfaceContainerHigh,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(highlighted ? palette.onPrimary : palette.onSurface)
        }
    }

    // MARK: - Media Now Playing Card

    @ViewBuilder
    private func mediaNowPlayingCard(for pc: PairedDevice) -> some View {
        if let players = store.state.media[pc.id], let player = players.first {
            let artData = player.art ?? player.artKey.flatMap { store.state.mediaArt[$0] }
            HStack(spacing: 14) {
                if let artData, let uiImg = UIImage(data: artData) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onAppear {
                            theme.updateArtwork(jpegOrPng: artData, cacheKey: player.artKey)
                        }
                } else {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(palette.primary)
                        .frame(width: 54, height: 54)
                        .background(palette.primaryContainer.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.title ?? player.app)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(1)
                    if let artist = player.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(palette.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer()

                HStack(spacing: 12) {
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
                            .font(.title)
                    }

                    Button {
                        store.mediaCommand(deviceId: pc.id, player: player.id, action: .next)
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                }
                .foregroundStyle(palette.primary)
            }
            .padding(14)
            .nectarCard(palette: palette, family: theme.family, cornerRadius: 20)
        }
    }

    // MARK: - Quick Send Card

    private func quickSendCard(for pc: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to \(pc.info.name)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.onSurface)

            if let suggestion = store.state.lastClipSuggestion {
                Button {
                    if let url = URL(string: suggestion.target) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("\(suggestion.actionLabel): \(suggestion.target)")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(palette.secondaryContainer, in: Capsule())
                    .foregroundStyle(palette.onSecondaryContainer)
                }
            }

            HStack(spacing: 10) {
                Button {
                    handoffFileImporter = false
                    showFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(palette.onPrimary)
                }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 10,
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.primaryContainer, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(palette.onPrimaryContainer)
                }
            }

            HStack(spacing: 10) {
                Button {
                    store.sendCurrentClipboard(to: pc.id)
                } label: {
                    Label("Pasteboard", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(palette.onSurface)
                }

                Button {
                    showLinkPrompt = true
                } label: {
                    Label("Send Link", systemImage: "safari")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(palette.onSurface)
                }

                Button {
                    handoffFileImporter = true
                    showFileImporter = true
                } label: {
                    Label("Handoff Doc", systemImage: "arrow.up.doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(palette.onSurface)
                }
            }
        }
        .padding(18)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
    }

    // MARK: - Recent Photos Strip

    @ViewBuilder
    private func recentPhotosStrip(for pc: PairedDevice) -> some View {
        if !store.state.recentPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Photos")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.onSurface)
                    Spacer()
                    Text("Tap to send")
                        .font(.caption2)
                        .foregroundStyle(palette.onSurfaceVariant)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.state.recentPhotos.prefix(12), id: \.id) { item in
                            Button {
                                store.sendPhotoAsset(to: pc.id, localIdentifier: item.id)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    if let jpeg = store.state.recentPhotoThumbs[item.id],
                                       let img = UIImage(data: jpeg) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 78, height: 78)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    } else {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(palette.surfaceContainerHigh)
                                            .frame(width: 78, height: 78)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundStyle(palette.onSurfaceVariant)
                                            )
                                    }
                                    if item.video {
                                        Image(systemName: "video.fill")
                                            .font(.caption2)
                                            .padding(4)
                                            .background(.ultraThinMaterial, in: Circle())
                                            .padding(4)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .nectarCard(palette: palette, family: theme.family, cornerRadius: 20)
        }
    }

    // MARK: - Transfers & Outgoing Queue Card

    private var transfersAndQueueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transfers & Send Queue")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                if !store.state.sendQueue.isEmpty {
                    Button("Retry Failed") {
                        store.retryAllFailedQueueItems()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.primary)
                }
            }

            ForEach(store.state.transfers, id: \.id) { transfer in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(transfer.names.first ?? "Transfer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)
                        Spacer()
                        if case .requested = transfer.status {
                            Button("Accept") {
                                store.acceptTransfer(id: transfer.id)
                            }
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(palette.primary, in: Capsule())
                            .foregroundStyle(palette.onPrimary)
                        } else if case .running = transfer.status {
                            Button {
                                store.pauseTransfer(id: transfer.id)
                            } label: {
                                Image(systemName: "pause.circle")
                            }
                            Button {
                                store.cancelTransfer(id: transfer.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                        } else if case .paused = transfer.status {
                            Button {
                                store.resumeTransfer(id: transfer.id)
                            } label: {
                                Image(systemName: "play.circle")
                            }
                        }
                    }

                    if transfer.total > 0 {
                        ProgressView(value: Double(transfer.done), total: Double(transfer.total))
                            .tint(palette.primary)
                    }
                }
                .padding(10)
                .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
            }

            ForEach(store.state.sendQueue, id: \.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)
                        Text(queueStatusLabel(item.status))
                            .font(.caption2)
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    Spacer()
                    Button {
                        store.retryQueueItem(id: item.id)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    Button {
                        store.cancelQueueItem(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }
                .foregroundStyle(palette.primary)
                .padding(10)
                .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 20)
    }

    private func queueStatusLabel(_ status: FfiQueueStatus) -> String {
        switch status {
        case .waiting: return "Waiting for connection…"
        case .sending: return "Sending…"
        case .failed(let error): return "Failed: \(error)"
        case .expired(let error): return "Expired: \(error)"
        }
    }

    // MARK: - LocalSend Peers Card

    private var localSendPeersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LocalSend LAN Devices", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button {
                    store.refreshLocalSend()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }

            ForEach(store.state.localSendPeers, id: \.id) { peer in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.alias)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(palette.onSurface)
                        Text(peer.deviceModel ?? "\(peer.host):\(peer.port)")
                            .font(.caption2)
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    Spacer()
                    Text(peer.protocolHttps ? "HTTPS" : "HTTP")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.secondaryContainer, in: Capsule())
                        .foregroundStyle(palette.onSecondaryContainer)
                }
                .padding(10)
                .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .nectarCard(palette: palette, family: theme.family, cornerRadius: 20)
    }
}
