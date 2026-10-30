import AVFoundation
import Contacts
import Foundation
import Network
import Photos
import UIKit

/// Monitors iOS battery state, network path changes (`NWPathMonitor`), and OS permissions.
final class SystemMonitors {
    static let shared = SystemMonitors()

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.nectarlink.network.monitor", qos: .utility)
    private weak var nodeRef: NectarlinkNode?
    private var batteryObservers: [NSObjectProtocol] = []

    private init() {
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }

    func start(node: NectarlinkNode) {
        self.nodeRef = node

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            guard let node = self?.nodeRef else { return }
            Task {
                await node.networkChanged()
            }
        }
        pathMonitor.start(queue: monitorQueue)

        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let center = NotificationCenter.default
            let levelObs = center.addObserver(
                forName: UIDevice.batteryLevelDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let node = self.nodeRef else { return }
                let battery = self.currentBattery()
                Task { await node.updateBattery(battery: battery) }
                IosToggles.shared.notifyChanged()
            }
            let stateObs = center.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let node = self.nodeRef else { return }
                let battery = self.currentBattery()
                Task { await node.updateBattery(battery: battery) }
                IosToggles.shared.notifyChanged()
            }
            self.batteryObservers = [levelObs, stateObs]
        }

        let initialBattery = currentBattery()
        Task {
            await node.updateBattery(battery: initialBattery)
        }
        refreshPermissions(node: node)
    }

    func stop() {
        pathMonitor.cancel()
        for obs in batteryObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        batteryObservers.removeAll()
    }

    func currentBattery() -> Battery {
        let levelRaw = UIDevice.current.batteryLevel
        let pct: UInt8
        if levelRaw < 0 {
            pct = 100
        } else {
            pct = UInt8(max(0, min(100, Int((levelRaw * 100.0).rounded()))))
        }
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full)
        return Battery(level: pct, charging: charging)
    }

    func currentCapabilities() -> [String] {
        var caps: [String] = [
            "clip.write",
            "clip.share",
            "storage.read",
            "storage.write",
            "mirror.capture",
            "mirror.audio.playback",
            "mirror.view",
            "mirror.hevc",
            "media.watch",
            "toggles.read",
            "toggles.flashlight",
            "toggles.volume",
            "toggles.brightness",
            "call.state",
            "call.log",
            "call.dial"
        ]
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            caps.append("camera.stream")
            caps.append("camera.capture")
            caps.append("webcam.hevc")
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            caps.append("mic.stream")
        }
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoStatus == .authorized || photoStatus == .limited {
            caps.append("photos.read")
        }
        if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            caps.append("contacts.read")
        }
        return caps
    }

    func refreshPermissions(node: NectarlinkNode? = nil) {
        guard let targetNode = node ?? nodeRef else { return }
        let caps = currentCapabilities()
        Task {
            await targetNode.updatePower(power: .basic, capabilities: caps)
        }
    }
}
