import AVFoundation
import Combine
import CoreMedia
import Foundation
import UIKit

/// Streams the iPhone front or back camera to a paired PC over `node.webcamOpen(pcId:)`.
final class WebcamStreamer: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = WebcamStreamer()

    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var activePcId: String?
    @Published private(set) var cameraFacing: String = "back"
    @Published private(set) var maxHeight: UInt32 = 1080
    @Published private(set) var fps: UInt32 = 30
    @Published private(set) var preferHevc: Bool = true
    @Published private(set) var zoomRatio: Float = 1.0
    @Published private(set) var maxZoomRatio: Float = 5.0
    @Published private(set) var torchEnabled: Bool = false
    @Published private(set) var hasTorch: Bool = false
    @Published private(set) var width: UInt32 = 1920
    @Published private(set) var height: UInt32 = 1080

    let captureSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "app.nectarlink.webcam.session", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "app.nectarlink.webcam.samples", qos: .userInteractive)
    private let lock = NSLock()

    private weak var nodeRef: NectarlinkNode?
    private var mirrorStream: MirrorStream?
    private var encoder: VideoToolboxEncoder?
    private var activeDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sentCodecHeader = false

    private override init() {
        super.init()
    }

    func attach(node: NectarlinkNode) {
        lock.lock()
        nodeRef = node
        lock.unlock()
    }

    static func hasPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start(
        pcId: String,
        camera: String = "back",
        maxHeight: UInt32 = 1080,
        fps: UInt32 = 30,
        preferHevc: Bool = true
    ) -> Bool {
        guard Self.hasPermission() else { return false }

        lock.lock()
        guard let node = nodeRef else {
            lock.unlock()
            return false
        }
        lock.unlock()

        guard let stream = try? node.webcamOpen(pcId: pcId) else {
            return false
        }

        let normalizedCamera = (camera.lowercased() == "front") ? "front" : "back"
        let clampedHeight: UInt32 = maxHeight >= 2160 ? 2160 : (maxHeight <= 720 ? 720 : 1080)
        let clampedFps: UInt32 = fps >= 60 ? 60 : 30

        sessionQueue.async { [weak self] in
            self?.configureAndStartSession(
                pcId: pcId,
                stream: stream,
                camera: normalizedCamera,
                maxHeight: clampedHeight,
                fps: clampedFps,
                preferHevc: preferHevc
            )
        }
        return true
    }

    func stop(pcId: String? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if let pcId, let current = self.activePcId, current != pcId {
                self.lock.unlock()
                return
            }
            let stream = self.mirrorStream
            let enc = self.encoder
            self.mirrorStream = nil
            self.encoder = nil
            self.activeDevice = nil
            self.sentCodecHeader = false
            self.lock.unlock()

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            enc?.stop()
            stream?.end()

            DispatchQueue.main.async {
                self.isStreaming = false
                self.activePcId = nil
                self.torchEnabled = false
                self.zoomRatio = 1.0
            }
        }
    }

    func requestKeyframe() {
        lock.lock()
        let enc = encoder
        lock.unlock()
        enc?.requestKeyFrame()
    }

    func applyControl(pcId: String, control: WebcamControlPayload) -> WebcamStatePayload {
        let semaphore = DispatchSemaphore(value: 0)
        var snapshot = currentStateSnapshot()

        sessionQueue.async { [weak self] in
            defer { semaphore.signal() }
            guard let self else { return }

            var needsRestart = false
            var targetCamera = self.cameraFacing
            var targetHeight = self.maxHeight
            var targetFps = self.fps

            if let requestedCam = control.camera {
                let normalized = requestedCam.lowercased() == "front" ? "front" : "back"
                if normalized != targetCamera {
                    targetCamera = normalized
                    needsRestart = true
                }
            }
            if let requestedHeight = control.maxHeight, requestedHeight != targetHeight {
                targetHeight = requestedHeight
                needsRestart = true
            }
            if let requestedFps = control.fps, requestedFps != targetFps {
                targetFps = requestedFps
                needsRestart = true
            }

            if needsRestart, let stream = self.mirrorStream {
                self.configureAndStartSession(
                    pcId: pcId,
                    stream: stream,
                    camera: targetCamera,
                    maxHeight: targetHeight,
                    fps: targetFps,
                    preferHevc: self.preferHevc
                )
            }

            if let device = self.activeDevice {
                do {
                    try device.lockForConfiguration()
                    if let requestedZoom = control.zoomRatio {
                        let maxZ = min(Float(device.activeFormat.videoMaxZoomFactor), 8.0)
                        let clamped = max(1.0, min(requestedZoom, maxZ))
                        device.videoZoomFactor = CGFloat(clamped)
                        DispatchQueue.main.async {
                            self.zoomRatio = clamped
                            self.maxZoomRatio = maxZ
                        }
                    }
                    if let requestedTorch = control.torch, device.hasTorch {
                        if requestedTorch && device.isTorchModeSupported(.on) {
                            try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                            DispatchQueue.main.async { self.torchEnabled = true }
                        } else if device.isTorchModeSupported(.off) {
                            device.torchMode = .off
                            DispatchQueue.main.async { self.torchEnabled = false }
                        }
                    }
                    if control.focusPoint != nil {
                        let point = CGPoint(
                            x: CGFloat(control.focusX ?? 0.5),
                            y: CGFloat(control.focusY ?? 0.5)
                        )
                        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                            device.focusPointOfInterest = point
                            device.focusMode = .autoFocus
                        }
                        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                            device.exposurePointOfInterest = point
                            device.exposureMode = .autoExpose
                        }
                    }
                    device.unlockForConfiguration()
                } catch {}
            }

            if let bitrateKbps = control.bitrateKbps {
                self.encoder?.setBitrate(Int(bitrateKbps) * 1_000)
            }

            snapshot = self.currentStateSnapshot()
        }

        _ = semaphore.wait(timeout: .now() + 1.5)
        return snapshot
    }

    func switchCamera() {
        guard let pcId = activePcId else { return }
        let next = cameraFacing == "back" ? "front" : "back"
        _ = applyControl(
            pcId: pcId,
            control: WebcamControlPayload(
                camera: next,
                torch: nil,
                zoomRatio: 1.0,
                maxHeight: nil,
                fps: nil,
                bitrateKbps: nil,
                focusPoint: nil,
                focusX: nil,
                focusY: nil
            )
        )
    }

    func setZoom(_ ratio: Float) {
        guard let pcId = activePcId else { return }
        _ = applyControl(
            pcId: pcId,
            control: WebcamControlPayload(
                camera: nil,
                torch: nil,
                zoomRatio: ratio,
                maxHeight: nil,
                fps: nil,
                bitrateKbps: nil,
                focusPoint: nil,
                focusX: nil,
                focusY: nil
            )
        )
    }

    func setTorch(_ enabled: Bool) {
        guard let pcId = activePcId else { return }
        _ = applyControl(
            pcId: pcId,
            control: WebcamControlPayload(
                camera: nil,
                torch: enabled,
                zoomRatio: nil,
                maxHeight: nil,
                fps: nil,
                bitrateKbps: nil,
                focusPoint: nil,
                focusX: nil,
                focusY: nil
            )
        )
    }

    func setResolution(maxHeight: UInt32, fps: UInt32 = 30) {
        guard let pcId = activePcId else {
            DispatchQueue.main.async {
                self.maxHeight = maxHeight
                self.fps = fps
            }
            return
        }
        _ = applyControl(
            pcId: pcId,
            control: WebcamControlPayload(
                camera: nil,
                torch: nil,
                zoomRatio: nil,
                maxHeight: maxHeight,
                fps: fps,
                bitrateKbps: nil,
                focusPoint: nil,
                focusX: nil,
                focusY: nil
            )
        )
    }

    private func configureAndStartSession(
        pcId: String,
        stream: MirrorStream,
        camera: String,
        maxHeight: UInt32,
        fps: UInt32,
        preferHevc: Bool
    ) {
        captureSession.beginConfiguration()

        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        let position: AVCaptureDevice.Position = (camera == "front") ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        let targetPreset: AVCaptureSession.Preset
        let encodedWidth: Int32
        let encodedHeight: Int32
        if maxHeight >= 2160 && captureSession.canSetSessionPreset(.hd4K3840x2160) {
            targetPreset = .hd4K3840x2160
            encodedWidth = 3840
            encodedHeight = 2160
        } else if maxHeight <= 720 && captureSession.canSetSessionPreset(.hd1280x720) {
            targetPreset = .hd1280x720
            encodedWidth = 1280
            encodedHeight = 720
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            targetPreset = .hd1920x1080
            encodedWidth = 1920
            encodedHeight = 1080
        } else {
            targetPreset = .high
            encodedWidth = 1280
            encodedHeight = 720
        }
        captureSession.sessionPreset = targetPreset

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }

        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (position == .front)
            }
        }

        do {
            try device.lockForConfiguration()
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
        } catch {}

        captureSession.commitConfiguration()

        let bitrate = encodedHeight >= 2160 ? 14_000_000 : (encodedHeight >= 1080 ? 6_000_000 : 3_200_000)
        let newEncoder = VideoToolboxEncoder(
            width: encodedWidth,
            height: encodedHeight,
            fps: Int32(fps),
            bitrateBps: bitrate,
            preferHevc: preferHevc
        ) { [weak self] kind, ptsUs, annexB in
            self?.handleEncodedPacket(kind: kind, ptsUs: ptsUs, data: annexB)
        }

        lock.lock()
        let oldEncoder = encoder
        encoder = newEncoder
        mirrorStream = stream
        activeDevice = device
        videoOutput = output
        sentCodecHeader = false
        lock.unlock()

        oldEncoder?.stop()

        if !captureSession.isRunning {
            captureSession.startRunning()
        }

        let maxZ = min(Float(device.activeFormat.videoMaxZoomFactor), 8.0)
        let torchSupported = device.hasTorch
        DispatchQueue.main.async {
            self.activePcId = pcId
            self.isStreaming = true
            self.cameraFacing = camera
            self.maxHeight = UInt32(encodedHeight)
            self.fps = fps
            self.preferHevc = preferHevc
            self.width = UInt32(encodedWidth)
            self.height = UInt32(encodedHeight)
            self.maxZoomRatio = maxZ
            self.zoomRatio = Float(device.videoZoomFactor)
            self.hasTorch = torchSupported
            self.torchEnabled = device.isTorchActive
        }
    }

    private func handleEncodedPacket(kind: VideoPacketKind, ptsUs: UInt64, data: Data) {
        lock.lock()
        guard let stream = mirrorStream, let enc = encoder else {
            lock.unlock()
            return
        }
        let needCodecHeader = !sentCodecHeader
        if needCodecHeader {
            sentCodecHeader = true
        }
        let camera = cameraFacing
        let maxH = maxHeight
        let targetFps = fps
        lock.unlock()

        if needCodecHeader {
            let header = webcamConfigCodec(
                codec: enc.codec.rawValue,
                width: UInt32(enc.width),
                height: UInt32(enc.height),
                camera: camera,
                fps: targetFps,
                maxHeight: maxH
            )
            _ = stream.send(kind: .config, timeUs: 0, data: header)
        }

        let result = stream.send(kind: kind, timeUs: ptsUs, data: data)
        switch result {
        case .needKeyframe:
            enc.requestKeyFrame()
        case .closed:
            stop()
        case .queued, .dropped:
            break
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        let enc = encoder
        lock.unlock()
        enc?.encode(sampleBuffer: sampleBuffer)
    }

    private func currentStateSnapshot() -> WebcamStatePayload {
        let device = activeDevice
        let maxZ = device.map { min(Float($0.activeFormat.videoMaxZoomFactor), 8.0) } ?? maxZoomRatio
        let currentZ = device.map { Float($0.videoZoomFactor) } ?? zoomRatio
        let torch = device?.isTorchActive ?? torchEnabled
        let torchAvail = device?.hasTorch ?? hasTorch
        return WebcamStatePayload(
            streaming: isStreaming,
            camera: cameraFacing,
            torch: torch,
            hasTorch: torchAvail,
            zoomRatio: currentZ,
            maxZoomRatio: maxZ,
            width: width,
            height: height,
            fps: fps,
            maxHeight: maxHeight
        )
    }
}
