// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// Reads and sets iPhone quick settings (`flashlight`, `brightness`, `volume`)
/// and reports `PhoneToggles` snapshots to connected PCs.
public final class IosToggles: NSObject, @unchecked Sendable {
    public static let shared = IosToggles()

    public var onTogglesChanged: (@Sendable (PhoneToggles) -> Void)?

    private var volumeObservation: NSKeyValueObservation?
    private var brightnessObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    public static var hasFlashlight: Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.hasTorch
    }

    public func startObserving() {
        DispatchQueue.main.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true, options: [])
            self.volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
                guard let self else { return }
                self.emitCurrent()
            }
            self.brightnessObserver = NotificationCenter.default.addObserver(
                forName: UIScreen.brightnessDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.emitCurrent()
            }
        }
    }

    public func stopObserving() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        if let brightnessObserver {
            NotificationCenter.default.removeObserver(brightnessObserver)
            self.brightnessObserver = nil
        }
    }

    public func currentSnapshot() -> PhoneToggles {
        var brightnessPct: UInt8 = 50
        let readBrightness = {
            let b = UIScreen.main.brightness
            brightnessPct = UInt8(max(0, min(100, Int((b * 100.0).rounded()))))
        }
        if Thread.isMainThread {
            readBrightness()
        } else {
            DispatchQueue.main.sync(execute: readBrightness)
        }

        let vol = AVAudioSession.sharedInstance().outputVolume
        let volumePct = UInt8(max(0, min(100, Int((vol * 100.0).rounded()))))

        let flashState: Bool?
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            flashState = device.torchMode == .on
        } else {
            flashState = nil
        }

        return PhoneToggles(
            dnd: false,
            ringer: "ring",
            flashlight: flashState,
            volume: volumePct,
            brightness: brightnessPct,
            wifi: true,
            bluetooth: true
        )
    }

    public func setToggle(id: String, value: PhoneToggleValue) -> Bool {
        switch (id, value) {
        case ("flashlight", .bool(let on)):
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
                return false
            }
            do {
                try device.lockForConfiguration()
                if on {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                emitCurrent()
                return true
            } catch {
                return false
            }

        case ("brightness", .level(let level)):
            let clamped = CGFloat(max(0, min(100, Int(level)))) / 100.0
            DispatchQueue.main.async {
                UIScreen.main.brightness = clamped
                self.emitCurrent()
            }
            return true

        case ("volume", .level(let level)):
            let clamped = Float(max(0, min(100, Int(level)))) / 100.0
            DispatchQueue.main.async {
                Self.setSystemVolume(clamped)
                self.emitCurrent()
            }
            return true

        default:
            return false
        }
    }

    private func emitCurrent() {
        let snapshot = currentSnapshot()
        onTogglesChanged?(snapshot)
    }

    @MainActor
    private static func setSystemVolume(_ volume: Float) {
        let volumeView = MPVolumeView(frame: .zero)
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.value = volume
        }
    }
}
