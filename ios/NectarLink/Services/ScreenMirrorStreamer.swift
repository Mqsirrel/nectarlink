import Combine
import CoreMedia
import Foundation
import ReplayKit
import UIKit

/// Streams the iPhone screen (and optional app audio) to a paired PC using `RPScreenRecorder`
/// and `VideoToolboxEncoder`.
final class ScreenMirrorStreamer: ObservableObject {
    static let shared = ScreenMirrorStreamer()

    @Published private(set) var isMirroring: Bool = false
    @Published private(set) var activePcId: String?

    private let lock = NSLock()
    private weak var nodeRef: NectarlinkNode?
    private var videoStream: MirrorStream?
    private var audioStream: MirrorStream?
    private var encoder: VideoToolboxEncoder?
    private var sentVideoHeader = false
    private var sentAudioHeader = false
    private var sessionCounter: UInt32 = 1

    private init() {}

    func attach(node: NectarlinkNode) {
        lock.lock()
        nodeRef = node
        lock.unlock()
    }

    func start(
        pcId: String,
        maxHeight: UInt32 = 1280,
        fps: UInt32 = 30,
        preferHevc: Bool = true,
        audio: Bool = false
    ) -> Bool {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { return false }

        lock.lock()
        guard let node = nodeRef else {
            lock.unlock()
            return false
        }
        lock.unlock()

        guard let vStream = try? node.mirrorOpen(pcId: pcId) else {
            return false
        }
        let aStream: MirrorStream? = audio ? (try? node.mirrorOpenAudio(pcId: pcId)) : nil

        let screenBounds = UIScreen.main.nativeBounds
        let rawW = max(320.0, Double(screenBounds.width))
        let rawH = max(320.0, Double(screenBounds.height))
        let targetMaxH = Double(max(480, min(maxHeight, 2160)))
        let scale = min(1.0, targetMaxH / max(rawW, rawH))
        let encW = Int32((rawW * scale).rounded()) & ~1
        let encH = Int32((rawH * scale).rounded()) & ~1

        guard let newEncoder = VideoToolboxEncoder(
            width: encW,
            height: encH,
            fps: Int32(max(15, min(fps, 60))),
            bitrateBps: 5_500_000,
            preferHevc: preferHevc,
            onPacket: { [weak self] kind, ptsUs, annexB in
                self?.handleVideoPacket(kind: kind, ptsUs: ptsUs, data: annexB)
            }
        ) else {
            vStream.end()
            aStream?.end()
            return false
        }

        lock.lock()
        let oldEncoder = encoder
        let oldV = videoStream
        let oldA = audioStream
        encoder = newEncoder
        videoStream = vStream
        audioStream = aStream
        sentVideoHeader = false
        sentAudioHeader = false
        sessionCounter &+= 1
        lock.unlock()

        oldEncoder?.stop()
        oldV?.end()
        oldA?.end()

        DispatchQueue.main.async {
            if recorder.isRecording {
                recorder.stopCapture(handler: nil)
            }
            recorder.isMicrophoneEnabled = false
            recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
                guard error == nil, let self else { return }
                switch bufferType {
                case .video:
                    self.lock.lock()
                    let enc = self.encoder
                    self.lock.unlock()
                    enc?.encode(sampleBuffer: sampleBuffer)
                case .audioApp:
                    self.handleAudioSample(sampleBuffer)
                default:
                    break
                }
            }, completionHandler: { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.stop(pcId: pcId)
                } else {
                    DispatchQueue.main.async {
                        self.isMirroring = true
                        self.activePcId = pcId
                    }
                }
            })
        }

        return true
    }

    func stop(pcId: String? = nil) {
        lock.lock()
        if let pcId, let active = activePcId, active != pcId {
            lock.unlock()
            return
        }
        let enc = encoder
        let vStream = videoStream
        let aStream = audioStream
        encoder = nil
        videoStream = nil
        audioStream = nil
        sentVideoHeader = false
        sentAudioHeader = false
        lock.unlock()

        DispatchQueue.main.async {
            let recorder = RPScreenRecorder.shared()
            if recorder.isRecording {
                recorder.stopCapture(handler: nil)
            }
            self.isMirroring = false
            self.activePcId = nil
        }

        enc?.stop()
        vStream?.end()
        aStream?.end()
    }

    func setQuality(pcId: String, maxHeight: UInt32?, fps: UInt32?, bitrateKbps: UInt32?) {
        lock.lock()
        let enc = encoder
        lock.unlock()
        if let bitrateKbps {
            enc?.setBitrate(Int(bitrateKbps) * 1_000)
        }
    }

    func requestKeyframe() {
        lock.lock()
        let enc = encoder
        lock.unlock()
        enc?.requestKeyFrame()
    }

    private func handleVideoPacket(kind: VideoPacketKind, ptsUs: UInt64, data: Data) {
        lock.lock()
        guard let vStream = videoStream, let enc = encoder else {
            lock.unlock()
            return
        }
        let needsHeader = !sentVideoHeader
        if needsHeader {
            sentVideoHeader = true
        }
        let session = sessionCounter
        lock.unlock()

        if needsHeader {
            let header = mirrorConfigCodec(
                codec: enc.codec.rawValue,
                width: UInt32(enc.width),
                height: UInt32(enc.height),
                session: session
            )
            _ = vStream.send(kind: .config, timeUs: 0, data: header)
        }

        let res = vStream.send(kind: kind, timeUs: ptsUs, data: data)
        switch res {
        case .needKeyframe:
            enc.requestKeyFrame()
        case .closed:
            stop()
        case .queued, .dropped:
            break
        }
    }

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard let aStream = audioStream else {
            lock.unlock()
            return
        }
        let needsHeader = !sentAudioHeader
        if needsHeader {
            sentAudioHeader = true
        }
        lock.unlock()

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return
        }

        if needsHeader {
            let rate = UInt32(max(8000, Int(asbd.mSampleRate)))
            let channels = UInt8(max(1, min(2, Int(asbd.mChannelsPerFrame))))
            let header = mirrorAudioConfig(rate: rate, channels: channels)
            _ = aStream.send(kind: .config, timeUs: 0, data: header)
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &ptr
        ) == kCMBlockBufferNoErr, let ptr, length > 0 else {
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsUs = UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000))
        let pcmData = Data(bytes: ptr, count: length)
        _ = aStream.send(kind: .frame, timeUs: ptsUs, data: pcmData)
    }
}
