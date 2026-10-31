// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import AudioToolbox
import Foundation
import UIKit
import UserNotifications

/// Rings the iPhone loudly (even when the silent switch is enabled, using
/// `AVAudioSession.Category.playback`) and vibrates until `stop()` is called.
public final class Ringer: @unchecked Sendable {
    public static let shared = Ringer()
    public static let stopNotificationActionId = "app.nectarlink.ios.action.STOP_RINGING"
    public static let notificationCategoryId = "app.nectarlink.ios.category.RINGING"

    public var onStopped: (() -> Void)?

    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private var vibrationTimer: DispatchSourceTimer?
    private var isRinging = false

    private init() {}

    public func start() {
        lock.lock()
        if isRinging {
            lock.unlock()
            return
        }
        isRinging = true
        lock.unlock()

        DispatchQueue.main.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true, options: [])

                let wavData = Self.makeChimeWavData()
                let audioPlayer = try AVAudioPlayer(data: wavData, fileTypeHint: AVFileType.wav.rawValue)
                audioPlayer.numberOfLoops = -1
                audioPlayer.volume = 1.0
                audioPlayer.prepareToPlay()
                audioPlayer.play()

                self.lock.lock()
                self.player = audioPlayer
                self.lock.unlock()
            } catch {
                // Fall back to system alert sound if audio session setup fails.
                AudioServicesPlayAlertSound(SystemSoundID(1005))
            }

            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(1200))
            timer.setEventHandler {
                AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            }
            timer.resume()

            self.lock.lock()
            self.vibrationTimer = timer
            self.lock.unlock()

            Self.postRingingNotification()
        }
    }

    public func stop() {
        lock.lock()
        let wasRinging = isRinging
        isRinging = false
        let currentPlayer = player
        let currentTimer = vibrationTimer
        player = nil
        vibrationTimer = nil
        lock.unlock()

        guard wasRinging else { return }

        DispatchQueue.main.async {
            currentTimer?.cancel()
            currentPlayer?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["nectarlink-ringing"])
            self.onStopped?()
        }
    }

    private static func postRingingNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Finding your iPhone"
        content.body = "A paired device is ringing this iPhone. Tap to stop."
        content.categoryIdentifier = notificationCategoryId
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "nectarlink-ringing",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Synthesises a 1.2-second two-note honey-chime (A5 880 Hz -> D6 1174.66 Hz) PCM-16LE WAV in memory.
    private static func makeChimeWavData() -> Data {
        let sampleRate = 44_100
        let durationSeconds = 1.2
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        var pcm = Data(capacity: numSamples * 2)

        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let freq: Double
            let env: Double
            if t < 0.35 {
                freq = 880.0
                env = min(1.0, t / 0.015) * exp(-t * 4.5)
            } else if t < 0.85 {
                let localT = t - 0.35
                freq = 1174.66
                env = min(1.0, localT / 0.015) * exp(-localT * 3.8)
            } else {
                freq = 0.0
                env = 0.0
            }
            let sample = sin(2.0 * .pi * freq * t) * 0.75 * env
            let clamped = Int16(max(-32767.0, min(32767.0, sample * 32767.0)))
            var le = clamped.littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }

        var wav = Data()
        let dataSize = UInt32(pcm.count)
        let chunkSize = 36 + dataSize
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(Self.u32le(chunkSize))
        wav.append("WAVEfmt ".data(using: .ascii)!)
        wav.append(Self.u32le(16))
        wav.append(Self.u16le(1)) // PCM
        wav.append(Self.u16le(1)) // Mono
        wav.append(Self.u32le(UInt32(sampleRate)))
        wav.append(Self.u32le(UInt32(sampleRate * 2)))
        wav.append(Self.u16le(2))
        wav.append(Self.u16le(16))
        wav.append("data".data(using: .ascii)!)
        wav.append(Self.u32le(dataSize))
        wav.append(pcm)
        return wav
    }

    private static func u16le(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    private static func u32le(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }
}
