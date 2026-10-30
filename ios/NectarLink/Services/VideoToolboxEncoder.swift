import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Hardware-accelerated H.264 / HEVC video encoder backed by Apple's `VideoToolbox`.
///
/// Converts `VTCompressionSession` AVCC/HVCC length-prefixed output into Annex-B
/// (`00 00 00 01`) byte streams expected by `MirrorStream.send(kind:timeUs:data:)`.
final class VideoToolboxEncoder {
    enum Codec: String {
        case h264 = "h264"
        case hevc = "h265"

        var cmCodecType: CMVideoCodecType {
            switch self {
            case .h264: return kCMVideoCodecType_H264
            case .hevc: return kCMVideoCodecType_HEVC
            }
        }
    }

    typealias PacketHandler = (_ kind: VideoPacketKind, _ ptsUs: UInt64, _ annexB: Data) -> Void

    let width: Int32
    let height: Int32
    let fps: Int32
    let codec: Codec

    private var session: VTCompressionSession?
    private let onPacket: PacketHandler
    private let lock = NSLock()
    private var forceNextKeyframe = true
    private var sentInitialConfig = false

    init?(
        width: Int32,
        height: Int32,
        fps: Int32 = 30,
        bitrateBps: Int = 5_000_000,
        preferHevc: Bool = true,
        onPacket: @escaping PacketHandler
    ) {
        self.width = max(16, width & ~1)
        self.height = max(16, height & ~1)
        self.fps = max(15, fps)
        self.onPacket = onPacket

        let chosenCodec: Codec = preferHevc ? .hevc : .h264
        var vtSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: self.width,
            height: self.height,
            codecType: chosenCodec.cmCodecType,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &vtSession
        )

        if status == noErr, let vtSession {
            self.codec = chosenCodec
            self.session = vtSession
        } else {
            var fallbackSession: VTCompressionSession?
            let fallbackStatus = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: self.width,
                height: self.height,
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &fallbackSession
            )
            guard fallbackStatus == noErr, let fallbackSession else {
                return nil
            }
            self.codec = .h264
            self.session = fallbackSession
        }

        configureSession(bitrateBps: bitrateBps)
    }

    deinit {
        stop()
    }

    private func configureSession(bitrateBps: Int) {
        guard let session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: NSNumber(value: fps * 2)
        )
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
            value: NSNumber(value: 2.0)
        )
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: NSNumber(value: fps)
        )
        setBitrate(bitrateBps)
        switch codec {
        case .h264:
            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_ProfileLevel,
                value: kVTProfileLevel_H264_High_AutoLevel
            )
        case .hevc:
            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_ProfileLevel,
                value: kVTProfileLevel_HEVC_Main_AutoLevel
            )
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    func setBitrate(_ bps: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let session else { return }
        let clamped = max(400_000, min(bps, 35_000_000))
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: NSNumber(value: clamped)
        )
        let bytesPerSecond = clamped / 8
        let limit: [NSNumber] = [NSNumber(value: bytesPerSecond * 2), NSNumber(value: 1.0)]
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_DataRateLimits,
            value: limit as CFArray
        )
    }

    func requestKeyFrame() {
        lock.lock()
        forceNextKeyframe = true
        lock.unlock()
    }

    func encode(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        encode(pixelBuffer: imageBuffer, presentationTimeStamp: pts, duration: duration)
    }

    func encode(
        pixelBuffer: CVImageBuffer,
        presentationTimeStamp pts: CMTime,
        duration: CMTime = .invalid
    ) {
        lock.lock()
        guard let session else {
            lock.unlock()
            return
        }
        let shouldForceKey = forceNextKeyframe
        forceNextKeyframe = false
        lock.unlock()

        var frameProps: CFDictionary?
        if shouldForceKey {
            frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
        }

        var infoFlags = VTEncodeInfoFlags()
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: frameProps,
            infoFlagsOut: &infoFlags
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer else { return }
            self?.handleEncodedSampleBuffer(sampleBuffer)
        }
    }

    func stop() {
        lock.lock()
        guard let session else {
            lock.unlock()
            return
        }
        self.session = nil
        lock.unlock()

        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
    }

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsSeconds = pts.isValid && pts.isNumeric ? CMTimeGetSeconds(pts) : CACurrentMediaTime()
        let ptsUs = UInt64(max(0, ptsSeconds * 1_000_000))

        let isKeyFrame = Self.isKeyFrame(sampleBuffer)
        if isKeyFrame || !sentInitialConfig {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let configAnnexB = Self.extractParameterSetsAnnexB(from: formatDesc, codec: codec) {
                sentInitialConfig = true
                onPacket(.config, ptsUs, configAnnexB)
            }
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        guard let annexBFrame = Self.convertLengthPrefixedToAnnexB(blockBuffer: blockBuffer) else { return }
        onPacket(isKeyFrame ? .keyframe : .frame, ptsUs, annexBFrame)
    }

    private static func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[CFString: Any]],
              let first = attachments.first else {
            return true
        }
        let notSync = (first[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        return !notSync
    }

    private static let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

    private static func extractParameterSetsAnnexB(
        from formatDesc: CMFormatDescription,
        codec: Codec
    ) -> Data? {
        var parameterSetCount = 0
        let countStatus: OSStatus
        switch codec {
        case .h264:
            countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &parameterSetCount,
                nalUnitHeaderLengthOut: nil
            )
        case .hevc:
            countStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &parameterSetCount,
                nalUnitHeaderLengthOut: nil
            )
        }
        guard countStatus == noErr, parameterSetCount > 0 else { return nil }

        var out = Data()
        for index in 0..<parameterSetCount {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            let status: OSStatus
            switch codec {
            case .h264:
                status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDesc,
                    parameterSetIndex: index,
                    parameterSetPointerOut: &ptr,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
            case .hevc:
                status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    formatDesc,
                    parameterSetIndex: index,
                    parameterSetPointerOut: &ptr,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
            }
            if status == noErr, let ptr, size > 0 {
                out.append(contentsOf: startCode)
                out.append(ptr, count: size)
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func convertLengthPrefixedToAnnexB(blockBuffer: CMBlockBuffer) -> Data? {
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer, totalLength > 4 else { return nil }

        let rawPtr = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: UInt8.self)
        var out = Data(capacity: totalLength + 16)
        var offset = 0
        while offset + 4 <= totalLength {
            let nalLength = Int(UInt32(rawPtr[offset]) << 24
                | UInt32(rawPtr[offset + 1]) << 16
                | UInt32(rawPtr[offset + 2]) << 8
                | UInt32(rawPtr[offset + 3]))
            offset += 4
            guard nalLength > 0, offset + nalLength <= totalLength else { break }
            out.append(contentsOf: startCode)
            out.append(rawPtr.advanced(by: offset), count: nalLength)
            offset += nalLength
        }
        return out.isEmpty ? nil : out
    }
}
