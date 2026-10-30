import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import Foundation
import SwiftUI
import UIKit
import VideoToolbox

/// Decodes incoming H.264 / HEVC Annex-B frames from a paired PC (`Event.pcMirrorFrame`)
/// using Apple's hardware `VTDecompressionSession` and renders them to the UI.
final class PcMirrorSession: ObservableObject {
    static let shared = PcMirrorSession()

    @Published var activePcId: String?
    @Published var isStreaming: Bool = false
    @Published var frameImage: CGImage?
    @Published var videoWidth: UInt32 = 1920
    @Published var videoHeight: UInt32 = 1080
    @Published var codecName: String = "h264"

    private let decodeQueue = DispatchQueue(label: "app.nectarlink.pcmirror.decode", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var audioRate: UInt32 = 48_000
    private var audioChannels: UInt8 = 2

    private init() {}

    func prepare(pcId: String) {
        DispatchQueue.main.async {
            self.activePcId = pcId
            self.isStreaming = true
        }
    }

    func onConfig(pcId: String, codec: String, width: UInt32, height: UInt32) {
        DispatchQueue.main.async {
            self.activePcId = pcId
            self.isStreaming = true
            self.codecName = codec
            self.videoWidth = max(1, width)
            self.videoHeight = max(1, height)
        }
    }

    func onFrame(pcId: String, keyframe: Bool, timeUs: UInt64, annexB: Data) {
        let currentCodec = codecName
        decodeQueue.async { [weak self] in
            self?.decodeAnnexB(annexB: annexB, isHevc: currentCodec.contains("265") || currentCodec.contains("hevc"))
        }
    }

    func onAudioConfig(pcId: String, rate: UInt32, channels: UInt8) {
        audioRate = rate
        audioChannels = channels
        PcSpeakerPlayer.shared.setListening(peerId: pcId, enabled: true)
    }

    func onAudioFrame(pcId: String, pcm: Data) {
        PcSpeakerPlayer.shared.onPcmFrame(
            fromId: pcId,
            sampleRate: audioRate,
            channels: audioChannels,
            pcm: pcm
        )
    }

    func onStopped(pcId: String) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            if let session = self.decompressionSession {
                VTDecompressionSessionInvalidate(session)
                self.decompressionSession = nil
            }
            self.formatDescription = nil
        }
        PcSpeakerPlayer.shared.stop(peerId: pcId)
        DispatchQueue.main.async {
            if self.activePcId == pcId || self.activePcId == nil {
                self.isStreaming = false
                self.activePcId = nil
                self.frameImage = nil
            }
        }
    }

    // MARK: - Annex-B to AVCC/HVCC Decompression

    private func decodeAnnexB(annexB: Data, isHevc: Bool) {
        let nalus = Self.splitAnnexBNalus(data: annexB)
        guard !nalus.isEmpty else { return }

        var vps: [UInt8]?
        var sps: [UInt8]?
        var pps: [UInt8]?
        var sliceNalus: [[UInt8]] = []

        for nalu in nalus {
            guard let first = nalu.first else { continue }
            if isHevc {
                let type = (first >> 1) & 0x3F
                if type == 32 {
                    vps = nalu
                } else if type == 33 {
                    sps = nalu
                } else if type == 34 {
                    pps = nalu
                } else if type <= 21 {
                    sliceNalus.append(nalu)
                }
            } else {
                let type = first & 0x1F
                if type == 7 {
                    sps = nalu
                } else if type == 8 {
                    pps = nalu
                } else if type == 1 || type == 5 {
                    sliceNalus.append(nalu)
                }
            }
        }

        if !isHevc, let sps, let pps {
            updateH264FormatDescription(sps: sps, pps: pps)
        } else if isHevc, let vps, let sps, let pps {
            updateHevcFormatDescription(vps: vps, sps: sps, pps: pps)
        }

        guard !sliceNalus.isEmpty,
              let formatDesc = formatDescription,
              let session = decompressionSession else {
            return
        }

        // Pack slice NALUs with 4-byte big-endian length prefixes
        var avccData = Data()
        for slice in sliceNalus {
            var lengthBE = UInt32(slice.count).bigEndian
            withUnsafeBytes(of: &lengthBE) { avccData.append(contentsOf: $0) }
            avccData.append(contentsOf: slice)
        }

        let dataCount = avccData.count
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return }

        let replaceStatus = avccData.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: dataCount
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else { return }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = dataCount
        let sbStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let sampleBuffer else { return }

        var infoFlags = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &infoFlags
        ) { [weak self] decodeStatus, _, imageBuffer, _, _ in
            guard decodeStatus == noErr, let imageBuffer, let self else { return }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            if let cgImg = self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                DispatchQueue.main.async {
                    self.frameImage = cgImg
                }
            }
        }
    }

    private func updateH264FormatDescription(sps: [UInt8], pps: [UInt8]) {
        var newDesc: CMFormatDescription?
        let status: OSStatus = sps.withUnsafeBufferPointer { spsBuf in
            pps.withUnsafeBufferPointer { ppsBuf in
                guard let spsPtr = spsBuf.baseAddress, let ppsPtr = ppsBuf.baseAddress else {
                    return -1
                }
                let pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let sizes: [Int] = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newDesc
                )
            }
        }
        if status == noErr, let newDesc {
            recreateDecompressionSession(with: newDesc)
        }
    }

    private func updateHevcFormatDescription(vps: [UInt8], sps: [UInt8], pps: [UInt8]) {
        var newDesc: CMFormatDescription?
        let status: OSStatus = vps.withUnsafeBufferPointer { vpsBuf in
            sps.withUnsafeBufferPointer { spsBuf in
                pps.withUnsafeBufferPointer { ppsBuf in
                    guard let vpsPtr = vpsBuf.baseAddress,
                          let spsPtr = spsBuf.baseAddress,
                          let ppsPtr = ppsBuf.baseAddress else {
                        return -1
                    }
                    let pointers: [UnsafePointer<UInt8>] = [vpsPtr, spsPtr, ppsPtr]
                    let sizes: [Int] = [vps.count, sps.count, pps.count]
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: pointers,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &newDesc
                    )
                }
            }
        }
        if status == noErr, let newDesc {
            recreateDecompressionSession(with: newDesc)
        }
    }

    private func recreateDecompressionSession(with desc: CMFormatDescription) {
        if let oldDesc = formatDescription, CMFormatDescriptionEqual(oldDesc, otherFormatDescription: desc) {
            return
        }
        if let existing = decompressionSession {
            VTDecompressionSessionInvalidate(existing)
            decompressionSession = nil
        }
        formatDescription = desc
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: desc,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )
        if status == noErr {
            decompressionSession = newSession
        }
    }

    private static func splitAnnexBNalus(data: Data) -> [[UInt8]] {
        let bytes = [UInt8](data)
        let n = bytes.count
        guard n >= 4 else { return [] }

        var starts: [(offset: Int, prefixLen: Int)] = []
        var i = 0
        while i + 3 <= n {
            if bytes[i] == 0 && bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 {
                    starts.append((i, 3))
                    i += 3
                    continue
                } else if i + 4 <= n && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                    starts.append((i, 4))
                    i += 4
                    continue
                }
            }
            i += 1
        }

        var nalus: [[UInt8]] = []
        for idx in 0..<starts.count {
            let payloadStart = starts[idx].offset + starts[idx].prefixLen
            let payloadEnd = (idx + 1 < starts.count) ? starts[idx + 1].offset : n
            if payloadStart < payloadEnd {
                nalus.append(Array(bytes[payloadStart..<payloadEnd]))
            }
        }
        return nalus
    }
}

/// Interactive PC-to-iPhone screen mirror view with direct touch injection.
struct PcMirrorView: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var session = PcMirrorSession.shared
    let pcId: String
    let watchPlayer: String?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let cgImage = session.frameImage {
                GeometryReader { geo in
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let normX = Float(max(0, min(1, value.location.x / max(1, geo.size.width))))
                                    let normY = Float(max(0, min(1, value.location.y / max(1, geo.size.height))))
                                    store.sendPcMirrorTouch(pcId: pcId, phase: .move, x: normX, y: normY)
                                }
                                .onEnded { value in
                                    let normX = Float(max(0, min(1, value.location.x / max(1, geo.size.width))))
                                    let normY = Float(max(0, min(1, value.location.y / max(1, geo.size.height))))
                                    store.sendPcMirrorTouch(pcId: pcId, phase: .up, x: normX, y: normY)
                                }
                        )
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("Connecting to PC Display…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            VStack {
                HStack {
                    Button {
                        store.stopPcMirror(pcId: pcId)
                        onClose()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button {
                        if let node = store.node {
                            Task { try? await node.requestPcMirrorKeyframe(pcId: pcId) }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            store.startPcMirror(pcId: pcId, watchPlayer: watchPlayer)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            store.stopPcMirror(pcId: pcId)
        }
    }
}
