// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct PairingPeerInfo: Equatable, Sendable {
    public let id: String
    public var name: String { id }
}

public struct PairingPrompt: Equatable, Sendable {
    public let peerId: String
    public let code: String

    public var peerName: String { peerId }
    public var peer: PairingPeerInfo { PairingPeerInfo(id: peerId) }
}

public struct PcMirrorStreamConfig: Equatable, Sendable {
    public let pcId: String
    public let codec: String
    public let width: UInt32
    public let height: UInt32
}

public struct QueueDroppedBanner: Equatable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let droppedCount: UInt32
}

public struct CameraCapturePrompt: Equatable, Identifiable, Sendable {
    public var id: String { "\(pcId):\(requestId)" }
    public let pcId: String
    public let requestId: String
    /// `"photo"` or `"scan"`.
    public let mode: String
}

public struct WatchOfferPrompt: Equatable, Identifiable, Sendable {
    public var id: String { "\(fromId):\(player)" }
    public let fromId: String
    public let player: String
    public let title: String?
    public let file: WatchFileOffer?
}

public typealias WatchOfferState = WatchOfferPrompt

/// Snapshot of everything the iOS UI renders from the Rust `NectarlinkNode`.
public struct CoreState: Equatable, Sendable {
    public var ready: Bool = false
    public var startupError: String? = nil
    public var deviceId: String = ""
    public var paired: [PairedDevice] = []
    public var discovered: [DiscoveredDevice] = []
    public var capabilities: [String: [String: FeatureStatus]] = [:]
    public var batteries: [String: Battery] = [:]
    public var media: [String: [MediaPlayer]] = [:]
    public var transfers: [Transfer] = []
    public var sendQueue: [FfiQueueItem] = []
    public var pairingCode: PairingPrompt? = nil
    public var pairingQrLink: String? = nil
    public var pairingError: PairingFailure? = nil
    public var pairingBusy: Bool = false
    public var ringing: Bool = false
    public var awayMode: Bool = true
    public var clipboardHistory: [ClipboardHistoryEntry] = []
    public var clipboardHistoryEnabled: Bool = true
    public var lastClipSuggestion: ClipSuggestion? = nil
    public var deckLayouts: [String: DeckLayout] = [:]
    public var deckStates: [String: DeckState] = [:]
    public var timelineEntries: [TimelineEntry] = []
    public var timelineTotal: UInt32 = 0
    public var timelineHasMore: Bool = false
    public var timelineRetentionDays: UInt32 = 30
    public var timelineRetention: TimelineRetention? = nil
    public var dataRetentionCounts: DataRetentionCounts? = nil
    public var localSendEnabled: Bool = false
    public var localSendReceiving: Bool = false
    public var localSendPeers: [LocalSendPeer] = []
    public var pcMirrorConfigs: [String: PcMirrorStreamConfig] = [:]
    public var pcAudioListeningDevice: String? = nil
    public var pcSpeakerPeers: Set<String> = []
    public var mediaArt: [String: Data] = [:]
    public var recentPhotos: [PhotoItem] = []
    public var recentPhotoThumbs: [String: Data] = [:]
    public var deviceToggles: [String: [String: Bool]] = [:]
    public var storagePromptPeerId: String? = nil
    public var queueDroppedBanner: QueueDroppedBanner? = nil
    public var activeCameraCapture: CameraCapturePrompt? = nil
    public var activeWatchOffer: WatchOfferPrompt? = nil
    public var webcamStreamingPcId: String? = nil
    public var screenMirroringPcId: String? = nil
    public var micStreamingPcId: String? = nil

    public var myId: String {
        get { deviceId }
        set { deviceId = newValue }
    }

    public var myQrLink: String? {
        get { pairingQrLink }
        set { pairingQrLink = newValue }
    }

    public var pairingPrompt: PairingPrompt? {
        get { pairingCode }
        set { pairingCode = newValue }
    }

    public var watchOffer: WatchOfferPrompt? {
        get { activeWatchOffer }
        set { activeWatchOffer = newValue }
    }

    public var dataRetention: DataRetentionCounts? {
        get { dataRetentionCounts }
        set { dataRetentionCounts = newValue }
    }

    public mutating func fold(_ event: Event) {
        apply(event)
    }

    public init() {}

    /// Paired devices that are currently online.
    public var onlineDevices: [PairedDevice] {
        paired.filter { device in
            if case .online = device.link { return true }
            return false
        }
    }

    /// Paired devices where `featureId` is `.available` or `.partial` (or capabilities haven't arrived yet).
    public func devicesFor(_ featureId: String) -> [PairedDevice] {
        paired.filter { dev in
            guard let status = capabilities[dev.id]?[featureId] else { return true }
            switch status {
            case .available, .partial:
                return true
            case .locked, .unsupported:
                return false
            }
        }
    }

    /// Online paired devices where `featureId` is `.available` or `.partial`.
    public func onlineDevicesFor(_ featureId: String) -> [PairedDevice] {
        onlineDevices.filter { dev in
            guard let status = capabilities[dev.id]?[featureId] else { return true }
            switch status {
            case .available, .partial:
                return true
            case .locked, .unsupported:
                return false
            }
        }
    }

    /// Pure state transition for a core `Event`.
    public mutating func apply(_ event: Event) {
        switch event {
        case .deviceAdded(let device):
            if let idx = paired.firstIndex(where: { $0.id == device.id }) {
                paired[idx] = device
            } else {
                paired.append(device)
            }

        case .deviceRemoved(let id):
            paired.removeAll { $0.id == id }
            capabilities.removeValue(forKey: id)
            batteries.removeValue(forKey: id)
            media.removeValue(forKey: id)
            deckLayouts.removeValue(forKey: id)
            deckStates.removeValue(forKey: id)
            pcMirrorConfigs.removeValue(forKey: id)
            if pcAudioListeningDevice == id {
                pcAudioListeningDevice = nil
            }

        case .linkChanged(let id, let link):
            if let idx = paired.firstIndex(where: { $0.id == id }) {
                paired[idx].link = link
            }
            if case .offline = link {
                media.removeValue(forKey: id)
                pcMirrorConfigs.removeValue(forKey: id)
                if pcAudioListeningDevice == id {
                    pcAudioListeningDevice = nil
                }
            }

        case .peerInfoChanged(let id, let info):
            if let idx = paired.firstIndex(where: { $0.id == id }) {
                paired[idx].info = info
            }

        case .peerPowerChanged:
            break

        case .battery(let id, let battery):
            batteries[id] = battery

        case .ring(_, let on):
            ringing = on

        case .discovered(let device):
            if let idx = discovered.firstIndex(where: { $0.id == device.id }) {
                discovered[idx] = device
            } else {
                discovered.append(device)
            }

        case .discoveryExpired(let id):
            discovered.removeAll { $0.id == id }

        case .pairingCode(let peer, let code):
            pairingCode = PairingPrompt(peerId: peer, code: code)
            pairingError = nil

        case .paired(let device):
            if let idx = paired.firstIndex(where: { $0.id == device.id }) {
                paired[idx] = device
            } else {
                paired.append(device)
            }
            pairingCode = nil
            pairingQrLink = nil
            pairingError = nil

        case .pairingFailed(let failure):
            pairingCode = nil
            pairingError = failure

        case .capabilities(let id, let features):
            var map: [String: FeatureStatus] = [:]
            for f in features {
                map[f.id] = f.status
            }
            capabilities[id] = map

        case .notificationsReset, .notificationPosted, .notificationRemoved:
            break

        case .clipboardReceived, .clipboardHistoryChanged:
            break

        case .transfer(let transfer):
            if let idx = transfers.firstIndex(where: { $0.id == transfer.id }) {
                transfers[idx] = transfer
            } else {
                transfers.insert(transfer, at: 0)
                if transfers.count > 40 {
                    transfers.removeLast(transfers.count - 40)
                }
            }

        case .mediaChanged(let id, let players):
            var merged: [MediaPlayer] = []
            let prev = media[id] ?? []
            for var player in players {
                if player.art == nil,
                   let key = player.artKey,
                   let prevArt = prev.first(where: { $0.id == player.id && $0.artKey == key })?.art {
                    player.art = prevArt
                }
                merged.append(player)
            }
            media[id] = merged

        case .photoAdded, .callChanged, .callLogChanged, .contactsChanged,
             .mirroring, .smsChanged, .photosChanged, .remoteInputRequested,
             .phoneToggles, .webcam, .storageChanged:
            break

        case .wakeInfoChanged(let id, let canWake):
            if let idx = paired.firstIndex(where: { $0.id == id }) {
                paired[idx].canWake = canWake
            }

        case .reconnectChanged(let id, let on):
            if let idx = paired.firstIndex(where: { $0.id == id }) {
                paired[idx].reconnect = on
            }

        case .deckLayout(let id, let layout):
            deckLayouts[id] = layout

        case .deckState(let id, let state):
            deckStates[id] = state

        case .storageRequested(let id):
            storagePromptPeerId = id

        case .timelineChanged, .localSendChanged, .queueChanged:
            break

        case .pcAudioFrame:
            break

        case .pcMirrorConfig(let id, let codec, let width, let height):
            pcMirrorConfigs[id] = PcMirrorStreamConfig(pcId: id, codec: codec, width: width, height: height)

        case .pcMirrorFrame:
            break

        case .pcMirrorEnded(let id):
            pcMirrorConfigs.removeValue(forKey: id)

        case .queueDroppedOnUnpair(let deviceId, let deviceName, let droppedCount):
            queueDroppedBanner = QueueDroppedBanner(
                deviceId: deviceId,
                deviceName: deviceName,
                droppedCount: droppedCount
            )
        }
    }
}
