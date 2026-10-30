import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import UserNotifications
import Vision

/// Manages Continuity Camera (`camera.capture` / `"photo"` & `"scan"`) requests from paired PCs.
final class ContinuityCameraManager: ObservableObject {
    static let shared = ContinuityCameraManager()

    struct CaptureRequest: Identifiable, Equatable {
        let pcId: String
        let requestId: String
        let mode: String // "photo" or "scan"
        var id: String { requestId }
    }

    @Published var activeRequest: CaptureRequest?

    private weak var nodeRef: NectarlinkNode?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    func attach(node: NectarlinkNode) {
        self.nodeRef = node
    }

    func handleIncomingRequest(pcId: String, requestId: String, mode: String) -> Bool {
        let normalizedMode = (mode == "scan") ? "scan" : "photo"
        let request = CaptureRequest(pcId: pcId, requestId: requestId, mode: normalizedMode)

        DispatchQueue.main.async {
            self.activeRequest = request
            if UIApplication.shared.applicationState != .active {
                self.postLocalCaptureNotification(mode: normalizedMode)
            }
        }
        return true
    }

    func presentManualCapture(pcId: String, mode: String) {
        let reqId = UUID().uuidString
        let normalizedMode = (mode == "scan") ? "scan" : "photo"
        DispatchQueue.main.async {
            self.activeRequest = CaptureRequest(pcId: pcId, requestId: reqId, mode: normalizedMode)
        }
    }

    func completeCapture(image: UIImage) {
        guard let request = activeRequest, let node = nodeRef else {
            DispatchQueue.main.async { self.activeRequest = nil }
            return
        }
        DispatchQueue.main.async { self.activeRequest = nil }

        Task.detached(priority: .userInitiated) {
            let processed: UIImage
            if request.mode == "scan" {
                processed = Self.enhanceScannedDocument(image: image, context: self.ciContext)
            } else {
                processed = image
            }

            guard let jpeg = processed.jpegData(compressionQuality: 0.88) else {
                try? await node.cancelCameraCapture(
                    peerId: request.pcId,
                    requestId: request.requestId,
                    reason: "Failed to encode JPEG"
                )
                return
            }

            let width = UInt32(max(1, Int(processed.size.width * processed.scale)))
            let height = UInt32(max(1, Int(processed.size.height * processed.scale)))
            let timestamp = Int(Date().timeIntervalSince1970)
            let prefix = request.mode == "scan" ? "Scan" : "Photo"
            let fileName = "\(prefix)_\(timestamp).jpg"

            do {
                try await node.sendCameraCaptureResult(
                    pcId: request.pcId,
                    requestId: request.requestId,
                    mode: request.mode,
                    fileName: fileName,
                    mime: "image/jpeg",
                    width: width,
                    height: height,
                    data: jpeg
                )
            } catch {
                try? await node.cancelCameraCapture(
                    peerId: request.pcId,
                    requestId: request.requestId,
                    reason: error.localizedDescription
                )
            }
        }
    }

    func cancelActiveRequest(reason: String = "Cancelled on iPhone") {
        guard let request = activeRequest else { return }
        DispatchQueue.main.async { self.activeRequest = nil }
        guard let node = nodeRef else { return }
        Task {
            try? await node.cancelCameraCapture(
                peerId: request.pcId,
                requestId: request.requestId,
                reason: reason
            )
        }
    }

    /// Detects document rectangle boundaries with `Vision` and applies perspective correction
    /// and clean document contrast adjustment via `CoreImage`.
    static func enhanceScannedDocument(image: UIImage, context: CIContext) -> UIImage {
        guard let ciInput = CIImage(image: image) else { return image }
        let oriented = ciInput.oriented(forExifOrientation: exifOrientation(for: image.imageOrientation))

        var working = oriented
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.65
        request.minimumAspectRatio = 0.3
        request.maximumObservations = 1

        let handler = VNImageRequestHandler(ciImage: oriented, options: [:])
        if (try? handler.perform([request])) != nil,
           let rect = request.results?.first {
            let extent = oriented.extent
            func denorm(_ pt: CGPoint) -> CGPoint {
                CGPoint(
                    x: extent.origin.x + pt.x * extent.size.width,
                    y: extent.origin.y + pt.y * extent.size.height
                )
            }
            let perspective = CIFilter.perspectiveCorrection()
            perspective.inputImage = oriented
            perspective.topLeft = denorm(rect.topLeft)
            perspective.topRight = denorm(rect.topRight)
            perspective.bottomLeft = denorm(rect.bottomLeft)
            perspective.bottomRight = denorm(rect.bottomRight)
            if let corrected = perspective.outputImage {
                working = corrected
            }
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = working
        controls.contrast = 1.25
        controls.brightness = 0.04
        controls.saturation = 0.85
        let output = controls.outputImage ?? working

        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: cgImage)
    }

    private static func exifOrientation(for orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }

    private func postLocalCaptureNotification(mode: String) {
        let content = UNMutableNotificationContent()
        content.title = mode == "scan" ? "Scan Document for PC" : "Take Photo for PC"
        content.body = "Tap to open the camera and send directly to your PC."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "app.nectarlink.continuity.camera",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
