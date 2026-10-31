// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import Combine
import Foundation

public struct SavedVoiceRecording: Identifiable, Equatable, Sendable {
    public let id: String
    public let fileURL: URL
    public let fileName: String
    public let createdAt: Date
    public let durationMs: UInt64
    public let sizeBytes: UInt64
    public let markers: [RecordingMarker]
    public var sentToDevices: [String]
}

/// Records 48 kHz AAC (`.m4a`) voice notes with timestamped markers, live
/// waveform levels, local playback, and automatic delivery to paired PCs.
@MainActor
public final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    public static let shared = VoiceRecorder()

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var isPaused: Bool = false

    /// Latest normalised input level (0...1) for the live meter.
    public var amplitude: Float { waveformSamples.last ?? 0 }
    @Published public private(set) var elapsedMs: UInt64 = 0
    @Published public private(set) var currentMarkers: [RecordingMarker] = []
    public var markers: [RecordingMarker] { currentMarkers }
    @Published public private(set) var waveformSamples: [Float] = Array(repeating: 0.08, count: 40)
    @Published public private(set) var recordings: [SavedVoiceRecording] = []
    @Published public private(set) var playingRecordingId: String? = nil

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var recordingStartDate: Date?
    private var currentFileURL: URL?

    private override init() {
        super.init()
        loadExistingRecordings()
    }

    public func startRecording() async -> Bool {
        guard !isRecording else { return true }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return false }

        stopPlayback()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let fileName = "VoiceNote_\(formatter.string(from: Date())).m4a"
            let destURL = recordingsDirectory().appendingPathComponent(fileName)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            let rec = try AVAudioRecorder(url: destURL, settings: settings)
            rec.delegate = self
            rec.isMeteringEnabled = true
            guard rec.record() else { return false }

            self.recorder = rec
            self.currentFileURL = destURL
            self.recordingStartDate = Date()
            self.elapsedMs = 0
            self.currentMarkers = []
            self.waveformSamples = Array(repeating: 0.08, count: 40)
            self.isRecording = true
            self.isPaused = false

            self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tickMeters()
                }
            }
            return true
        } catch {
            return false
        }
    }

    public func pauseRecording() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        meterTimer?.invalidate()
        meterTimer = nil
        isPaused = true
    }

    public func resumeRecording() {
        guard isRecording, isPaused else { return }
        recorder?.record()
        isPaused = false
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickMeters()
            }
        }
    }

    public func addMarker(label: String? = nil) {
        guard isRecording else { return }
        let cleaned = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = RecordingMarker(
            atMs: elapsedMs,
            label: (cleaned?.isEmpty == false) ? cleaned : "Marker \(currentMarkers.count + 1)"
        )
        currentMarkers.append(marker)
    }

    public func stopRecording() -> SavedVoiceRecording? {
        guard isRecording, let rec = recorder, let url = currentFileURL else { return nil }
        meterTimer?.invalidate()
        meterTimer = nil
        let finalDurationMs = elapsedMs
        let markers = currentMarkers
        rec.stop()
        self.recorder = nil
        self.isRecording = false
        self.isPaused = false
        self.currentFileURL = nil

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let saved = SavedVoiceRecording(
            id: url.lastPathComponent,
            fileURL: url,
            fileName: url.lastPathComponent,
            createdAt: Date(),
            durationMs: max(500, finalDurationMs),
            sizeBytes: size,
            markers: markers,
            sentToDevices: []
        )
        saveMarkersSidecar(markers, for: url)
        recordings.insert(saved, at: 0)
        return saved
    }

    public func cancelRecording() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentFileURL = nil
        isRecording = false
        isPaused = false
        elapsedMs = 0
        currentMarkers = []
    }

    public func togglePlayback(_ item: SavedVoiceRecording) {
        if playingRecordingId == item.id {
            stopPlayback()
            return
        }
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: item.fileURL)
            p.delegate = self
            p.play()
            player = p
            playingRecordingId = item.id
        } catch {
            playingRecordingId = nil
        }
    }

    public func stopPlayback() {
        player?.stop()
        player = nil
        playingRecordingId = nil
    }

    public func deleteRecording(_ item: SavedVoiceRecording) {
        if playingRecordingId == item.id {
            stopPlayback()
        }
        try? FileManager.default.removeItem(at: item.fileURL)
        try? FileManager.default.removeItem(at: markersSidecarURL(for: item.fileURL))
        recordings.removeAll { $0.id == item.id }
    }

    public func markSent(_ recordingId: String, to deviceName: String) {
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        if !recordings[idx].sentToDevices.contains(deviceName) {
            recordings[idx].sentToDevices.append(deviceName)
        }
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playingRecordingId = nil
        }
    }

    private func tickMeters() {
        guard isRecording, let rec = recorder else { return }
        rec.updateMeters()
        if let start = recordingStartDate {
            elapsedMs = UInt64(max(0, Date().timeIntervalSince(start) * 1000.0))
        }
        let dB = rec.averagePower(forChannel: 0)
        // Map [-55 dB ... 0 dB] to [0.06 ... 1.0].
        let normalized = max(0.06, min(1.0, (dB + 55.0) / 55.0))
        var samples = waveformSamples
        if !samples.isEmpty {
            samples.removeFirst()
        }
        samples.append(normalized)
        waveformSamples = samples
    }

    private func recordingsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func markersSidecarURL(for audioURL: URL) -> URL {
        audioURL.appendingPathExtension("markers.json")
    }

    private func saveMarkersSidecar(_ markers: [RecordingMarker], for audioURL: URL) {
        let payload = markers.map { ["atMs": $0.atMs, "label": $0.label ?? ""] as [String: Any] }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: markersSidecarURL(for: audioURL))
        }
    }

    private func loadMarkersSidecar(for audioURL: URL) -> [RecordingMarker] {
        guard let data = try? Data(contentsOf: markersSidecarURL(for: audioURL)),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { dict in
            guard let atMs = (dict["atMs"] as? NSNumber)?.uint64Value else { return nil }
            let label = dict["label"] as? String
            return RecordingMarker(atMs: atMs, label: (label?.isEmpty == false) ? label : nil)
        }
    }

    private func loadExistingRecordings() {
        let dir = recordingsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var loaded: [SavedVoiceRecording] = []
        for url in files where url.pathExtension.lowercased() == "m4a" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = UInt64(max(0, values?.fileSize ?? 0))
            let created = values?.creationDate ?? Date()
            let asset = AVURLAsset(url: url)
            let durSec = CMTimeGetSeconds(asset.duration)
            let durMs = durSec.isFinite && durSec > 0 ? UInt64(durSec * 1000.0) : 1000
            let markers = loadMarkersSidecar(for: url)
            loaded.append(
                SavedVoiceRecording(
                    id: url.lastPathComponent,
                    fileURL: url,
                    fileName: url.lastPathComponent,
                    createdAt: created,
                    durationMs: durMs,
                    sizeBytes: size,
                    markers: markers,
                    sentToDevices: []
                )
            )
        }
        loaded.sort { $0.createdAt > $1.createdAt }
        self.recordings = loaded
    }
}
