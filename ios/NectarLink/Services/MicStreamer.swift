// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import Foundation

/// Captures 48 kHz mono 16-bit PCM from the iPhone microphone and streams it
/// to a paired PC (`node.micOpen(pcId:)`).
public final class MicStreamer: @unchecked Sendable {
    public static let shared = MicStreamer()

    public var onStateChanged: (@Sendable (_ pcId: String?) -> Void)?

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var stream: MirrorStream?
    private var activePcId: String?
    private var startTimeNs: UInt64 = 0

    private init() {}

    public var currentPcId: String? {
        lock.lock()
        defer { lock.unlock() }
        return activePcId
    }

    public func start(pcId: String, node: NectarlinkNode) async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return false }

        do {
            let mirrorStream = try await node.micOpen(pcId: pcId)
            let configBytes = mirrorAudioConfig(rate: 48_000, channels: 1)
            let cfgResult = mirrorStream.send(kind: .config, timeUs: 0, data: configBytes)
            if cfgResult == .closed {
                mirrorStream.end()
                return false
            }

            let started = startEngine(with: mirrorStream, pcId: pcId)
            if started {
                onStateChanged?(pcId)
            } else {
                mirrorStream.end()
            }
            return started
        } catch {
            return false
        }
    }

    public func stop(node: NectarlinkNode?) {
        lock.lock()
        let pcId = activePcId
        let currentStream = stream
        let currentEngine = engine
        activePcId = nil
        stream = nil
        engine = nil
        lock.unlock()

        currentEngine?.inputNode.removeTap(onBus: 0)
        currentEngine?.stop()
        currentStream?.end()

        if let pcId {
            onStateChanged?(nil)
            if let node {
                Task {
                    try? await node.micStop(pcId: pcId)
                }
            }
        }
    }

    private func startEngine(with mirrorStream: MirrorStream, pcId: String) -> Bool {
        stop(node: nil)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)

            let eng = AVAudioEngine()
            let input = eng.inputNode
            let hwFormat = input.inputFormat(forBus: 0)
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 48_000,
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
                return false
            }

            let startNs = DispatchTime.now().uptimeNanoseconds

            lock.lock()
            self.engine = eng
            self.stream = mirrorStream
            self.activePcId = pcId
            self.startTimeNs = startNs
            lock.unlock()

            input.installTap(onBus: 0, bufferSize: 960, format: hwFormat) { [weak self] buffer, _ in
                guard let self else { return }
                let ratio = 48_000.0 / max(1.0, hwFormat.sampleRate)
                let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else {
                    return
                }

                var error: NSError?
                var consumed = false
                converter.convert(to: outBuffer, error: &error) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                guard error == nil,
                      outBuffer.frameLength > 0,
                      let int16Ptr = outBuffer.int16ChannelData?[0] else {
                    return
                }

                let byteCount = Int(outBuffer.frameLength) * 2
                let data = Data(bytes: int16Ptr, count: byteCount)
                let elapsedUs = (DispatchTime.now().uptimeNanoseconds - startNs) / 1000

                self.lock.lock()
                let activeStream = self.stream
                self.lock.unlock()

                if let activeStream {
                    let res = activeStream.send(kind: .frame, timeUs: elapsedUs, data: data)
                    if res == .closed {
                        self.stop(node: nil)
                    }
                }
            }

            try eng.start()
            return true
        } catch {
            return false
        }
    }
}
