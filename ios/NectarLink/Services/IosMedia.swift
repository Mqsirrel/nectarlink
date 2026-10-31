// SPDX-License-Identifier: MPL-2.0

import Foundation
import MediaPlayer
import UIKit

/// Publishes the active paired PC's media player to `MPNowPlayingInfoCenter`
/// and wires `MPRemoteCommandCenter` so the user can control PC playback from
/// the iOS Lock Screen, Control Center, Dynamic Island, or AirPods.
@MainActor
public final class IosMedia {
    public static let shared = IosMedia()

    public var onRemoteCommand: ((_ deviceId: String, _ playerId: String, _ action: MediaAction, _ positionMs: UInt64?) -> Void)?
    public var onPlayersChanged: (@Sendable ([MediaPlayer]) -> Void)?

    private var activeDeviceId: String?
    private var activePlayer: MediaPlayer?
    private var commandsRegistered = false

    private init() {}

    public func updateNowPlaying(deviceId: String?, player: MediaPlayer?) {
        activeDeviceId = deviceId
        activePlayer = player

        guard let deviceId, let player, (player.title != nil || player.playing) else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        registerRemoteCommandsIfNeeded()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: player.title ?? player.app,
            MPMediaItemPropertyArtist: player.artist ?? player.app,
            MPNowPlayingInfoPropertyPlaybackRate: player.playing ? 1.0 : 0.0,
        ]
        if let album = player.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let durationMs = player.duration {
            info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
        }
        if let positionMs = player.position {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        }
        if let artData = player.art, let image = UIImage(data: artData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        _ = deviceId
    }

    private func registerRemoteCommandsIfNeeded() {
        guard !commandsRegistered else { return }
        commandsRegistered = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self, let dev = self.activeDeviceId, let p = self.activePlayer else {
                return .commandFailed
            }
            self.onRemoteCommand?(dev, p.id, .play, nil)
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, let dev = self.activeDeviceId, let p = self.activePlayer else {
                return .commandFailed
            }
            self.onRemoteCommand?(dev, p.id, .pause, nil)
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let dev = self.activeDeviceId, let p = self.activePlayer else {
                return .commandFailed
            }
            self.onRemoteCommand?(dev, p.id, p.playing ? .pause : .play, nil)
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, let dev = self.activeDeviceId, let p = self.activePlayer else {
                return .commandFailed
            }
            self.onRemoteCommand?(dev, p.id, .next, nil)
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, let dev = self.activeDeviceId, let p = self.activePlayer else {
                return .commandFailed
            }
            self.onRemoteCommand?(dev, p.id, .previous, nil)
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let posEvent = event as? MPChangePlaybackPositionCommandEvent,
                  let dev = self.activeDeviceId,
                  let p = self.activePlayer else {
                return .commandFailed
            }
            let ms = UInt64(max(0, posEvent.positionTime * 1000.0))
            self.onRemoteCommand?(dev, p.id, .seek, ms)
            return .success
        }
    }

    public func startObserving(onPlayersChanged: (@Sendable ([MediaPlayer]) -> Void)? = nil) {
        if let onPlayersChanged { self.onPlayersChanged = onPlayersChanged }
    }

    public func mediaCommand(player: String, action: MediaAction, position: UInt64?) throws {
        let sys = MPMusicPlayerController.systemMusicPlayer
        switch action {
        case .play: sys.play()
        case .pause, .stop: sys.pause()
        case .next: sys.skipToNextItem()
        case .previous: sys.skipToPreviousItem()
        case .seek:
            if let position {
                sys.currentPlaybackTime = Double(position) / 1000.0
            }
        default:
            break
        }
    }
}
