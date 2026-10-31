// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import Foundation

/// Low-latency PCM-16LE player for `Event.pcAudioFrame` ("Use iPhone as PC speaker").
public final class PcSpeakerPlayer: @unchecked Sendable {
    public static let shared = PcSpeakerPlayer()

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var activeDeviceId: String?
    private var currentSampleRate: UInt32 = 0
    private var currentChannels: UInt8 = 0

    private init() {}

    public var listeningDeviceId: String? {
        lock.lock()
        defer { lock.unlock() }
        return activeDeviceId
    }

    public func isListening(to peerId: String) -> Bool {
        listeningDeviceId == peerId
    }

    public func setListening(peerId: String, enabled: Bool) {
        setListeningDevice(enabled ? peerId : nil)
    }

    public func onPcmFrame(fromId: String, sampleRate: UInt32, channels: UInt8, pcm: Data) {
        enqueueFrame(device: fromId, sampleRate: sampleRate, channels: channels, pcm: pcm)
    }

    public func setListeningDevice(_ deviceId: String?) {
        lock.lock()
        activeDeviceId = deviceId
        if deviceId == nil {
            stopLocked()
        }
        lock.unlock()
    }

    public func enqueueFrame(device: String, sampleRate: UInt32, channels: UInt8, pcm: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard activeDeviceId == device, !pcm.isEmpty else { return }

        if engine == nil || currentSampleRate != sampleRate || currentChannels != channels {
            setupEngineLocked(sampleRate: sampleRate, channels: channels)
        }

        guard let playerNode, let format else { return }
        let chCount = Int(max(1, channels))
        let bytesPerFrame = chCount * 2
        let frameCount = pcm.count / bytesPerFrame
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let floatChannelData = buffer.floatChannelData else { return }
        pcm.withUnsafeBytes { rawBytes in
            guard let samples = rawBytes.bindMemory(to: Int16.self).baseAddress else { return }
            for frame in 0..<frameCount {
                for ch in 0..<chCount {
                    let s = Int16(littleEndian: samples[frame * chCount + ch])
                    floatChannelData[ch][frame] = Float(s) / 32768.0
                }
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    public func stop(peerId: String? = nil) {
        lock.lock()
        if let peerId, activeDeviceId != peerId {
            lock.unlock()
            return
        }
        activeDeviceId = nil
        stopLocked()
        lock.unlock()
    }

    private func setupEngineLocked(sampleRate: UInt32, channels: UInt8) {
        stopLocked()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)

            let eng = AVAudioEngine()
            let node = AVAudioPlayerNode()
            guard let fmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(max(1, channels)),
                interleaved: false
            ) else {
                return
            }

            eng.attach(node)
            eng.connect(node, to: eng.mainMixerNode, format: fmt)
            try eng.start()
            node.play()

            self.engine = eng
            self.playerNode = node
            self.format = fmt
            self.currentSampleRate = sampleRate
            self.currentChannels = channels
        } catch {
            stopLocked()
        }
    }

    private func stopLocked() {
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        format = nil
        currentSampleRate = 0
        currentChannels = 0
    }
}
