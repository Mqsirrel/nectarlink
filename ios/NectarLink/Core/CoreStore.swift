import Combine
import Foundation
import Photos
import UIKit

/// Main-actor observable store wrapping `NectarlinkNode` and driving the SwiftUI interface.
@MainActor
final class CoreStore: ObservableObject {
    static let shared = CoreStore()

    @Published var state = CoreState()
    @Published var selectedPcId: String?
    @Published var toastMessage: String?

    private(set) var node: NectarlinkNode?
    private var platform: IosPlatform?
    private var started = false

    /// Active paired PC (either user-selected, first connected, or first paired).
    var activePc: PairedDevice? {
        if let selectedPcId, let found = state.paired.first(where: { $0.id == selectedPcId }) {
            return found
        }
        if let connected = state.paired.first(where: { $0.link.isConnected }) {
            return connected
        }
        return state.paired.first
    }

    private init() {}

    func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    // MARK: - Startup

    func startIfNeeded() {
        guard !started else { return }
        started = true

        initLogging(filter: "info")
        Ringer.shared.onStopped = { [weak self] in
            Task { @MainActor in
                self?.state.ringing = false
            }
        }
        IosNotifications.shared.requestAuthorizationIfNeeded()

        let deviceName = UIDevice.current.name
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let osVer = UIDevice.current.systemVersion
        let modelName = UIDevice.current.model
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? "ios-default-vendor"
        let installId = installIdFrom(platformId: vendorId)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dataDir = appSupport.appendingPathComponent("NectarLinkCore", isDirectory: true)
        let downloadsDir = IosStorage.shared.rootDirectory.appendingPathComponent("Received", isDirectory: true)
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let awayDefault = UserDefaults.standard.object(forKey: "nectarlink.away_mode") as? Bool ?? true

        let options = NodeOptions(
            dataDir: dataDir.path,
            device: DeviceInfo(
                name: deviceName,
                kind: isPad ? .tablet : .phone,
                os: "ios",
                osVersion: osVer,
                model: modelName,
                accent: nil,
                screen: nil,
                installId: installId
            ),
            appVersion: appVersion,
            power: .basic,
            awayMode: awayDefault,
            downloadsDir: downloadsDir.path,
            usbPort: 53319
        )

        let iosPlatform = IosPlatform { [weak self] fromId, player, title, file in
            Task { @MainActor in
                self?.state.watchOffer = WatchOfferState(
                    fromId: fromId,
                    player: player,
                    title: title,
                    file: file
                )
            }
        }
        self.platform = iosPlatform
        let listener = ListenerBridge { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
        let protector = KeychainKeyProtector()

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let startedNode = try NectarlinkNode.start(
                    options: options,
                    platform: iosPlatform,
                    keyProtector: protector,
                    listener: listener
                )
                await MainActor.run {
                    self?.didStart(node: startedNode)
                }
            } catch {
                await MainActor.run {
                    self?.state.startupError = error.localizedDescription
                }
            }
        }
    }

    private func didStart(node: NectarlinkNode) {
        self.node = node
        self.state.myId = node.deviceId()
        self.state.ready = true
        self.state.awayMode = node.awayMode()

        // Wire services to the live node
        WebcamStreamer.shared.attach(node: node)
        ScreenMirrorStreamer.shared.attach(node: node)
        MicStreamer.shared.attach(node: node)
        ContinuityCameraManager.shared.attach(node: node)
        SystemMonitors.shared.start(node: node)

        IosPhotos.shared.startObserving(
            onPhotoTaken: { [weak node] photo in
                guard let node else { return }
                Task { try? await node.photoTaken(photo: photo) }
            },
            onPhotosChanged: { [weak node] in
                guard let node else { return }
                Task { await node.photosChanged() }
            }
        )

        IosCalls.shared.startObserving { [weak node] call in
            guard let node else { return }
            Task { try? await node.callChanged(call: call) }
        }

        IosToggles.shared.startObserving { [weak node] toggles in
            guard let node else { return }
            Task { try? await node.togglesChanged(toggles: toggles) }
        }

        IosMedia.shared.startObserving { [weak node] players in
            guard let node else { return }
            Task { await node.mediaChanged(players: players) }
        }

        reloadAllFromNode()
        consumeSharedInboxIfNeeded()
    }

    func reloadAllFromNode() {
        guard let node else { return }
        if let devices = try? node.pairedDevices() {
            state.paired = devices
            if selectedPcId == nil {
                selectedPcId = devices.first?.id
            }
            for dev in devices {
                if let caps = try? node.capabilities(id: dev.id) {
                    state.capabilities[dev.id] = caps
                }
                if let toggles = try? node.deviceToggles(id: dev.id) {
                    var map: [String: Bool] = [:]
                    for t in toggles {
                        map[t.name] = t.enabled
                    }
                    state.deviceToggles[dev.id] = map
                }
                if let layout = try? node.deckLayout(id: dev.id) {
                    state.deckLayouts[dev.id] = layout
                }
                if let deckSt = try? node.deckState(id: dev.id) {
                    state.deckStates[dev.id] = deckSt
                }
            }
        }
        state.discovered = node.discoveredDevices()
        state.sendQueue = (try? node.sendQueue(peerId: nil)) ?? []
        state.clipboardHistoryEnabled = node.clipboardHistoryEnabled()
        state.clipboardHistory = node.clipboardHistory(query: nil)
        state.lastClipSuggestion = node.lastClipSuggestion()
        state.localSendEnabled = node.localsendEnabled()
        state.localSendReceiving = node.localsendReceiving()
        state.localSendPeers = node.localsendPeers()
        state.awayMode = node.awayMode()
        state.timelineRetention = try? node.timelineRetention()
        state.dataRetention = node.dataRetentionCounts()
        if let page = try? node.timelinePage(kind: nil, deviceId: nil, search: nil, offset: 0, limit: 100) {
            state.timelineEntries = page.items
            state.timelineTotal = page.total
        }
        refreshRecentPhotos()
    }

    func refreshRecentPhotos() {
        Task.detached(priority: .utility) {
            let items = IosPhotos.shared.photoList(album: nil, before: nil, beforeId: "", limit: 16)
            let ids = items.map(\.id)
            let thumbs = IosPhotos.shared.photoThumbs(ids: ids)
            var thumbMap: [String: Data] = [:]
            for t in thumbs {
                thumbMap[t.id] = t.jpeg
            }
            await MainActor.run {
                self.state.recentPhotos = items
                for (k, v) in thumbMap {
                    self.state.recentPhotoThumbs[k] = v
                }
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: Event) {
        state.fold(event)

        switch event {
        case .paired(let device), .deviceAdded(let device):
            if selectedPcId == nil {
                selectedPcId = device.id
            }
            if let node {
                if let caps = try? node.capabilities(id: device.id) {
                    state.capabilities[device.id] = caps
                }
                if let toggles = try? node.deviceToggles(id: device.id) {
                    var map: [String: Bool] = [:]
                    for t in toggles {
                        map[t.name] = t.enabled
                    }
                    state.deviceToggles[device.id] = map
                }
            }

        case .deviceRemoved(let id):
            if selectedPcId == id {
                selectedPcId = state.paired.first?.id
            }
            PcSpeakerPlayer.shared.stop(peerId: id)

        case .linkChanged(let id, let link):
            if !link.isConnected {
                PcSpeakerPlayer.shared.stop(peerId: id)
            }

        case .queueChanged:
            if let node {
                state.sendQueue = (try? node.sendQueue(peerId: nil)) ?? []
            }

        case .clipboardHistoryChanged:
            if let node {
                state.clipboardHistory = node.clipboardHistory(query: nil)
                state.lastClipSuggestion = node.lastClipSuggestion()
                state.dataRetention = node.dataRetentionCounts()
            }

        case .timelineChanged:
            if let node {
                if let page = try? node.timelinePage(kind: nil, deviceId: nil, search: nil, offset: 0, limit: 100) {
                    state.timelineEntries = page.items
                    state.timelineTotal = page.total
                }
                state.dataRetention = node.dataRetentionCounts()
            }

        case .localSendChanged:
            if let node {
                state.localSendEnabled = node.localsendEnabled()
                state.localSendReceiving = node.localsendReceiving()
                state.localSendPeers = node.localsendPeers()
            }

        case .pcAudioPcm(let id, let sampleRate, let channels, let pcm):
            PcSpeakerPlayer.shared.onPcmFrame(
                fromId: id,
                sampleRate: sampleRate,
                channels: channels,
                pcm: pcm
            )

        case .pcMirrorConfig(let id, let codec, let width, let height):
            PcMirrorSession.shared.onConfig(pcId: id, codec: codec, width: width, height: height)

        case .pcMirrorFrame(let id, let keyframe, let timeUs, let data):
            PcMirrorSession.shared.onFrame(pcId: id, keyframe: keyframe, timeUs: timeUs, annexB: data)

        case .pcMirrorAudioConfig(let id, let rate, let channels):
            PcMirrorSession.shared.onAudioConfig(pcId: id, rate: rate, channels: channels)

        case .pcMirrorAudioFrame(let id, let pcm):
            PcMirrorSession.shared.onAudioFrame(pcId: id, pcm: pcm)

        case .pcMirrorStopped(let id):
            PcMirrorSession.shared.onStopped(pcId: id)

        case .transfer(let transfer):
            if transfer.direction == .incoming, case .done = transfer.status {
                let firstName = transfer.names.first ?? "File"
                showToast("Received \(firstName)")
            }

        default:
            break
        }
    }

    // MARK: - Pairing Actions

    func startQrPairing() {
        guard let node else { return }
        Task {
            do {
                let uri = try await node.pairingStartQr()
                self.state.myQrLink = uri
            } catch {
                self.state.pairingError = error.localizedDescription
            }
        }
    }

    func joinPairing(link: String) {
        guard let node else { return }
        state.pairingBusy = true
        state.pairingError = nil
        Task {
            do {
                try await node.pairingJoin(link: link)
            } catch {
                self.state.pairingBusy = false
                self.state.pairingError = error.localizedDescription
            }
        }
    }

    func startNearbyPairing(peerId: String) {
        guard let node else { return }
        state.pairingBusy = true
        state.pairingError = nil
        Task {
            do {
                try await node.pairingStartNearby(peer: peerId)
            } catch {
                self.state.pairingBusy = false
                self.state.pairingError = error.localizedDescription
            }
        }
    }

    func confirmPairing(match: Bool) {
        guard let node else { return }
        do {
            try node.pairingConfirm(codesMatch: match)
            if !match {
                state.pairingPrompt = nil
                state.pairingBusy = false
            }
        } catch {
            state.pairingError = error.localizedDescription
        }
    }

    func cancelPairing() {
        node?.pairingCancel()
        state.pairingPrompt = nil
        state.pairingBusy = false
        state.myQrLink = nil
    }

    func unpair(id: String) {
        guard let node else { return }
        Task {
            try? await node.unpair(id: id)
        }
    }

    // MARK: - Device & Connection Controls

    func refresh() {
        guard let node else { return }
        SystemMonitors.shared.refreshPermissions(node: node)
        refreshRecentPhotos()
        Task {
            await node.refresh()
        }
    }

    func setDeviceToggle(deviceId: String, name: String, enabled: Bool) {
        guard let node else { return }
        do {
            try node.setDeviceToggle(id: deviceId, name: name, enabled: enabled)
            var current = state.deviceToggles[deviceId] ?? [:]
            current[name] = enabled
            state.deviceToggles[deviceId] = current
            if let caps = try? node.capabilities(id: deviceId) {
                state.capabilities[deviceId] = caps
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func setReconnect(deviceId: String, on: Bool) {
        try? node?.setReconnect(id: deviceId, on: on)
    }

    func setAwayMode(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "nectarlink.away_mode")
        node?.setAwayMode(enabled: enabled)
        state.awayMode = enabled
    }

    func setLocalSendEnabled(_ enabled: Bool) {
        guard let node else { return }
        try? node.setLocalsendEnabled(enabled: enabled)
        state.localSendEnabled = node.localsendEnabled()
        state.localSendReceiving = node.localsendReceiving()
        state.localSendPeers = node.localsendPeers()
    }

    func refreshLocalSend() {
        node?.refreshLocalsend()
        if let node {
            state.localSendPeers = node.localsendPeers()
        }
    }

    func probeLocalSendPeer(host: String, port: UInt16 = 53317) {
        guard let node else { return }
        Task {
            if let _ = try? await node.probeLocalsendPeer(host: host, port: port) {
                self.state.localSendPeers = node.localsendPeers()
                self.showToast("Found LocalSend peer at \(host)")
            } else {
                self.showToast("No LocalSend peer responded at \(host):\(port)")
            }
        }
    }

    // MARK: - Ringing, Power, Wake-on-LAN & Audio

    func stopPhoneRinging() {
        Ringer.shared.stop()
        state.ringing = false
    }

    func ringPeer(id: String, on: Bool) {
        guard let node else { return }
        Task {
            try? await node.ring(id: id, on: on)
        }
    }

    func lockPc(id: String) {
        guard let node else { return }
        Task {
            do {
                try await node.pcPower(id: id, sleep: false)
                showToast("Locked PC")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func sleepPc(id: String) {
        guard let node else { return }
        Task {
            do {
                try await node.pcPower(id: id, sleep: true)
                showToast("Put PC to sleep")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func wakePc(id: String) {
        guard let node else { return }
        Task {
            do {
                try await node.wake(id: id)
                showToast("Sent Wake-on-LAN packet")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func setPcAudio(id: String, volume: UInt8?, muted: Bool?) {
        guard let node else { return }
        Task {
            try? await node.setPcAudio(id: id, volume: volume, muted: muted)
        }
    }

    func togglePcSpeaker(pcId: String) {
        let enabled = !PcSpeakerPlayer.shared.isListening(to: pcId)
        PcSpeakerPlayer.shared.setListening(peerId: pcId, enabled: enabled)
        if enabled {
            state.pcSpeakerPeers.insert(pcId)
            showToast("Phone speaker relay enabled")
        } else {
            state.pcSpeakerPeers.remove(pcId)
            showToast("Phone speaker relay stopped")
        }
    }

    // MARK: - Sending Files, Photos, Clipboard, Links & Voice Recordings

    func sendFiles(to peerId: String, urls: [URL], handoff: Bool = false) {
        guard let node, !urls.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let stagingDir = fm.temporaryDirectory.appendingPathComponent("NectarLinkSend", isDirectory: true)
            try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            var outgoing: [FileToSend] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                let fileName = url.lastPathComponent.isEmpty ? "File" : url.lastPathComponent
                let stagedUrl = stagingDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")
                do {
                    if fm.fileExists(atPath: stagedUrl.path) {
                        try fm.removeItem(at: stagedUrl)
                    }
                    try fm.copyItem(at: url, to: stagedUrl)
                    let attrs = try fm.attributesOfItem(atPath: stagedUrl.path)
                    let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                    outgoing.append(
                        FileToSend(
                            path: stagedUrl.path,
                            name: fileName,
                            size: size,
                            folder: nil
                        )
                    )
                } catch {}
            }

            guard !outgoing.isEmpty else { return }
            do {
                if handoff && outgoing.count == 1 && isSafeHandoffDocument(name: outgoing[0].name) {
                    _ = try await node.sendHandoffFiles(id: peerId, files: outgoing)
                    await MainActor.run {
                        self.showToast("Sent & opening \(outgoing[0].name) on PC")
                    }
                } else {
                    _ = try await node.sendFiles(id: peerId, files: outgoing)
                    await MainActor.run {
                        self.showToast("Sending \(outgoing.count) file(s)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    func sendPhotoAsset(to peerId: String, localIdentifier: String) {
        guard let node else { return }
        Task.detached(priority: .userInitiated) {
            guard let file = IosPhotos.shared.openPhoto(id: localIdentifier) else {
                await MainActor.run { self.showToast("Could not export photo") }
                return
            }
            do {
                _ = try await node.sendFiles(id: peerId, files: [file])
                await MainActor.run { self.showToast("Sending \(file.name)") }
            } catch {
                await MainActor.run { self.showToast(error.localizedDescription) }
            }
        }
    }

    func sendCurrentClipboard(to peerId: String) {
        guard let node else { return }
        let snap = IosClipboard.shared.readCurrentClipboard()
        Task {
            do {
                if let imageBytes = snap.imageBytes, let mime = snap.imageMime {
                    try await node.sendClipboardImage(id: peerId, mime: mime, bytes: imageBytes)
                    showToast("Clipboard image sent to PC")
                } else if let text = snap.text, !text.isEmpty {
                    try await node.sendClipboardRich(id: peerId, text: text, html: snap.html, rtf: snap.rtf)
                    showToast("Clipboard sent to PC")
                } else {
                    showToast("Clipboard is empty")
                }
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func sendTextClip(to peerId: String, text: String) {
        guard let node, !text.isEmpty else { return }
        Task {
            do {
                try await node.sendClipboard(id: peerId, text: text)
                showToast("Sent to PC clipboard")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func sendLink(to peerId: String, url: String) {
        guard let node else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolvedUrl: String
        if let handoff = extractHandoffLink(text: trimmed) {
            resolvedUrl = handoff.url
        } else if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            resolvedUrl = trimmed
        } else {
            resolvedUrl = "https://\(trimmed)"
        }
        Task {
            do {
                try await node.openLink(id: peerId, url: resolvedUrl)
                showToast("Opened link on PC")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func sendRecording(to peerId: String, fileUrl: URL, markers: [RecordingMarker]) {
        guard let node else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let file = FileToSend(
            path: fileUrl.path,
            name: fileUrl.lastPathComponent,
            size: size,
            folder: nil
        )
        Task {
            do {
                _ = try await node.sendRecording(id: peerId, file: file, markers: markers)
                showToast("Voice recording sent to PC")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    // MARK: - Transfers & Outgoing Queue

    func acceptTransfer(id: String) {
        node?.acceptTransfer(transferId: id)
    }

    func pauseTransfer(id: String) {
        node?.pauseTransfer(transferId: id)
    }

    func resumeTransfer(id: String) {
        node?.resumeTransfer(transferId: id)
    }

    func cancelTransfer(id: String) {
        node?.cancelTransfer(transferId: id)
    }

    func cancelQueueItem(id: String) {
        _ = try? node?.cancelQueueItem(id: id)
        if let node {
            state.sendQueue = (try? node.sendQueue(peerId: nil)) ?? []
        }
    }

    func retryQueueItem(id: String) {
        _ = try? node?.retryQueueItem(id: id)
        if let node {
            state.sendQueue = (try? node.sendQueue(peerId: nil)) ?? []
        }
    }

    func retryAllFailedQueueItems() {
        _ = try? node?.retryAllFailedQueueItems(peerId: nil)
        if let node {
            state.sendQueue = (try? node.sendQueue(peerId: nil)) ?? []
        }
    }

    func clearFinishedQueueItems() {
        _ = try? node?.clearFinishedQueueItems(peerId: nil)
        if let node {
            state.sendQueue = (try? node.sendQueue(peerId: nil)) ?? []
        }
    }

    // MARK: - Remote Input, Media & Deck

    func remoteMove(dx: Float, dy: Float) {
        guard let node, let pcId = activePc?.id else { return }
        Task {
            try? await node.remoteMove(id: pcId, dx: dx, dy: dy)
        }
    }

    func remoteScroll(dx: Float, dy: Float, fast: Bool = true) {
        guard let node, let pcId = activePc?.id else { return }
        Task {
            try? await node.remoteScroll(id: pcId, dx: dx, dy: dy, fast: fast)
        }
    }

    func remoteButton(button: String, action: String) {
        guard let node, let pcId = activePc?.id else { return }
        Task {
            try? await node.remoteButton(id: pcId, button: button, action: action)
        }
    }

    func remoteText(_ text: String) {
        guard let node, let pcId = activePc?.id, !text.isEmpty else { return }
        Task {
            try? await node.remoteText(id: pcId, text: text)
        }
    }

    func remoteKey(key: String, mods: [String] = []) {
        guard let node, let pcId = activePc?.id else { return }
        Task {
            try? await node.remoteKey(id: pcId, key: key, mods: mods)
        }
    }

    func remoteSlide(action: String) {
        guard let node, let pcId = activePc?.id else { return }
        Task {
            try? await node.remoteSlide(id: pcId, action: action)
        }
    }

    func remoteLaser(on: Bool, x: Float, y: Float) {
        guard let node, let pcId = activePc?.id else { return }
        Task {
            try? await node.remoteLaser(id: pcId, on: on, x: x, y: y)
        }
    }

    func deckPress(tileId: String) {
        guard let node, let pcId = activePc?.id else { return }
        Task {
            try? await node.deckPress(id: pcId, tile: tileId)
        }
    }

    func mediaCommand(deviceId: String, player: String, action: MediaAction, position: UInt64? = nil) {
        guard let node else { return }
        Task {
            try? await node.mediaCommand(id: deviceId, player: player, action: action, position: position)
        }
    }

    // MARK: - PC-to-Phone Screen Mirroring (`PcMirrorSession`)

    func startPcMirror(pcId: String, watchPlayer: String? = nil) {
        guard let node else { return }
        PcMirrorSession.shared.prepare(pcId: pcId)
        Task {
            do {
                try await node.startPcMirror(
                    pcId: pcId,
                    maxSize: 1920,
                    fps: 30,
                    bitrate: 6_000_000,
                    watch: watchPlayer
                )
            } catch {
                PcMirrorSession.shared.onStopped(pcId: pcId)
                showToast(error.localizedDescription)
            }
        }
    }

    func stopPcMirror(pcId: String) {
        PcMirrorSession.shared.onStopped(pcId: pcId)
        guard let node else { return }
        Task {
            try? await node.mirrorStop(pcId: pcId, session: 0)
        }
    }

    func sendPcMirrorTouch(pcId: String, phase: TouchPhase, x: Float, y: Float, pointerId: UInt32 = 0) {
        guard let node else { return }
        let ev = MirrorInputEvent.touch(phase: phase, x: x, y: y, id: pointerId)
        Task {
            try? await node.sendPcMirrorInput(pcId: pcId, input: ev)
        }
    }

    // MARK: - Clipboard History, Timeline, Remote PC Files & Privacy

    func setClipboardHistoryEnabled(_ enabled: Bool) {
        guard let node else { return }
        try? node.setClipboardHistoryEnabled(enabled: enabled)
        state.clipboardHistoryEnabled = node.clipboardHistoryEnabled()
        state.clipboardHistory = node.clipboardHistory(query: nil)
    }

    func searchClipboardHistory(query: String?) {
        guard let node else { return }
        let q = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.clipboardHistory = node.clipboardHistory(query: (q?.isEmpty == false) ? q : nil)
    }

    func pinClip(id: String, pinned: Bool) {
        guard let node else { return }
        _ = node.pinClipboardHistory(id: id, pinned: pinned)
        state.clipboardHistory = node.clipboardHistory(query: nil)
    }

    func deleteClip(id: String) {
        guard let node else { return }
        _ = node.deleteClipboardHistory(id: id)
        state.clipboardHistory = node.clipboardHistory(query: nil)
    }

    func copyClipToPhone(id: String) {
        guard let node else { return }
        do {
            try node.copyClipboardHistory(id: id)
            showToast("Copied to iPhone clipboard")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func resendClip(id: String, to peerId: String) {
        guard let node else { return }
        Task {
            do {
                try await node.resendClipboardHistory(clipId: id, deviceId: peerId)
                showToast("Sent clip to PC")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func clearClipboardHistory() {
        try? node?.clearClipboardHistory()
        if let node {
            state.clipboardHistory = node.clipboardHistory(query: nil)
            state.dataRetention = node.dataRetentionCounts()
        }
    }

    func queryTimeline(kind: TimelineKind? = nil, deviceId: String? = nil, search: String? = nil) {
        guard let node else { return }
        let q = search?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let page = try? node.timelinePage(
            kind: kind,
            deviceId: deviceId,
            search: (q?.isEmpty == false) ? q : nil,
            offset: 0,
            limit: 100
        ) {
            state.timelineEntries = page.items
            state.timelineTotal = page.total
        }
    }

    func deleteTimelineEntry(id: Int64) {
        _ = try? node?.deleteTimelineEntry(id: id)
        queryTimeline()
    }

    func clearTimeline() {
        try? node?.clearTimeline()
        queryTimeline()
    }

    func setTimelineRetention(maxDays: UInt32, maxEntries: UInt32) {
        try? node?.setTimelineRetention(maxDays: maxDays, maxEntries: maxEntries)
        state.timelineRetention = try? node?.timelineRetention()
    }

    func clearAllLocalData() {
        try? node?.clearAllLocalData()
        reloadAllFromNode()
        showToast("Cleared local history & caches")
    }

    func listRemoteStorage(peerId: String, path: String) async throws -> [RemoteStorageEntry] {
        guard let node else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            try node.listRemoteStorage(peer: peerId, path: path)
        }.value
    }

    func downloadRemoteStorage(peerId: String, remotePath: String, fileName: String) async -> URL? {
        guard let node else { return nil }
        let destDir = IosStorage.shared.rootDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destUrl = destDir.appendingPathComponent(fileName)
        let ok = await Task.detached(priority: .userInitiated) {
            node.downloadRemoteStorage(peer: peerId, remotePath: remotePath, localDest: destUrl.path)
        }.value
        return ok ? destUrl : nil
    }

    // MARK: - App Group Share Extension Inbox

    func consumeSharedInboxIfNeeded() {
        guard let peerId = activePc?.id else { return }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: IosStorage.appGroupIdentifier
        ) else {
            return
        }
        let inboxDir = container.appendingPathComponent("ShareInbox", isDirectory: true)
        let manifestUrl = inboxDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestUrl.path),
              let data = try? Data(contentsOf: manifestUrl),
              let items = try? JSONDecoder().decode([SharedInboxItem].self, from: data),
              !items.isEmpty else {
            return
        }

        try? FileManager.default.removeItem(at: manifestUrl)

        var fileUrls: [URL] = []
        for item in items {
            switch item.kind {
            case "url":
                if let urlStr = item.value {
                    sendLink(to: peerId, url: urlStr)
                }
            case "text":
                if let text = item.value {
                    sendTextClip(to: peerId, text: text)
                }
            case "file":
                if let relName = item.value {
                    let fileUrl = inboxDir.appendingPathComponent(relName)
                    if FileManager.default.fileExists(atPath: fileUrl.path) {
                        fileUrls.append(fileUrl)
                    }
                }
            default:
                break
            }
        }

        if !fileUrls.isEmpty {
            sendFiles(to: peerId, urls: fileUrls, handoff: false)
        }
    }
}

struct SharedInboxItem: Codable {
    let kind: String // "file", "url", "text"
    let value: String?
}

private final class ListenerBridge: EventListener, @unchecked Sendable {
    private let handler: (Event) -> Void

    init(handler: @escaping (Event) -> Void) {
        self.handler = handler
    }

    func onEvent(event: Event) {
        handler(event)
    }
}
