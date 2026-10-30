import Foundation
import UIKit

/// Implements the UniFFI `Platform` callback protocol on iOS, bridging Rust core requests
/// to native iOS services (`Ringer`, `IosClipboard`, `IosPhotos`, `IosContacts`, `IosCalls`,
/// `IosToggles`, `IosStorage`, `IosNotifications`, `IosMedia`, `WebcamStreamer`,
/// `ScreenMirrorStreamer`, `MicStreamer`, and `ContinuityCameraManager`).
final class IosPlatform: Platform, @unchecked Sendable {
    var onWatchOffered: ((String, String, String?, WatchFileOffer?) -> Void)?

    init(onWatchOffered: ((String, String, String?, WatchFileOffer?) -> Void)? = nil) {
        self.onWatchOffered = onWatchOffered
    }

    // MARK: - Find My Phone Ringing

    func startRinging() {
        Ringer.shared.start()
    }

    func stopRinging() {
        Ringer.shared.stop()
    }

    // MARK: - Notifications (Android-only listener; unsupported on iOS)

    func dismissNotification(key: String) throws {
        try IosNotifications.shared.dismissNotification(key: key)
    }

    func runNotificationAction(key: String, action: String, reply: String?) throws {
        try IosNotifications.shared.runNotificationAction(key: key, action: action, reply: reply)
    }

    // MARK: - Clipboard

    func setClipboard(text: String) -> Bool {
        IosClipboard.shared.setClipboard(text: text)
    }

    func setClipboardRich(text: String, html: String?, rtf: String?) -> Bool {
        IosClipboard.shared.setClipboardRich(text: text, html: html, rtf: rtf)
    }

    func setClipboardImage(mime: String, bytes: Data) -> Bool {
        IosClipboard.shared.setClipboardImage(mime: mime, bytes: bytes)
    }

    // MARK: - Media

    func mediaCommand(player: String, action: MediaAction, position: UInt64?) throws {
        try IosMedia.shared.mediaCommand(player: player, action: action, position: position)
    }

    // MARK: - Links, Watch on Phone & Task Notifications

    func openLink(fromId: String, url: String) -> Bool {
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel" else {
            return false
        }
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                UIApplication.shared.open(parsed, options: [:], completionHandler: nil)
            } else {
                IosNotifications.shared.showLinkNotification(fromName: "Paired PC", url: url)
            }
        }
        return true
    }

    func watchOffered(fromId: String, player: String, title: String?, file: WatchFileOffer?) -> Bool {
        onWatchOffered?(fromId, player, title, file)
        IosNotifications.shared.showWatchOfferNotification(fromName: "Paired PC", title: title ?? player)
        return true
    }

    func taskNotify(fromId: String, task: TaskNotify) -> Bool {
        IosNotifications.shared.taskNotify(fromId: fromId, task: task)
    }

    // MARK: - Photo Gallery (`Photos` framework)

    func openPhoto(id: String) -> FileToSend? {
        IosPhotos.shared.openPhoto(id: id)
    }

    func photoAlbums() -> [PhotoAlbum] {
        IosPhotos.shared.photoAlbums()
    }

    func photoList(album: String?, before: Int64?, beforeId: String, limit: UInt32) -> [PhotoItem] {
        IosPhotos.shared.photoList(album: album, before: before, beforeId: beforeId, limit: limit)
    }

    func photoThumbs(ids: [String]) -> [PhotoThumb] {
        IosPhotos.shared.photoThumbs(ids: ids)
    }

    // MARK: - Calls (`CallKit` observer + `tel://` dialer)

    func callCommand(id: String, command: CallCommand) -> Bool {
        IosCalls.shared.callCommand(id: id, command: command)
    }

    func callLog(before: Int64?, limit: UInt32) -> [CallLogEntry] {
        IosCalls.shared.callLog(before: before, limit: limit)
    }

    func callDial(number: String) -> Bool {
        IosCalls.shared.callDial(number: number)
    }

    // MARK: - Contacts (`CNContactStore`)

    func contacts(query: String?, offset: UInt32, limit: UInt32) -> [Contact] {
        IosContacts.shared.contacts(query: query, offset: offset, limit: limit)
    }

    // MARK: - Screen Mirroring (`ReplayKit`)

    func mirrorRequested(pcId: String, options: MirrorOptions) -> Bool {
        guard options.session == 0 else {
            // Virtual display per-app windows are Android-only.
            return false
        }
        if options.stayAwake {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        return ScreenMirrorStreamer.shared.start(
            pcId: pcId,
            maxHeight: options.maxSize,
            fps: options.fps,
            preferHevc: true,
            audio: options.audio
        )
    }

    func mirrorStopRequested(pcId: String, session: UInt32) {
        guard session == 0 else { return }
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        ScreenMirrorStreamer.shared.stop(pcId: pcId)
    }

    func mirrorKeyframeRequested(pcId: String, session: UInt32) {
        guard session == 0 else { return }
        ScreenMirrorStreamer.shared.requestKeyframe()
    }

    func mirrorResizeRequested(pcId: String, session: UInt32, width: UInt32, height: UInt32) {
        // App window resize is Android-only.
    }

    func mirrorPowerRequested(pcId: String, stayAwake: Bool, screenOff: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = stayAwake
        }
    }

    func mirrorInput(pcId: String, session: UInt32, input: MirrorInputEvent) {
        // iOS does not allow synthetic touch injection outside the app process.
    }

    // MARK: - Camera as PC Webcam (`AVCaptureSession` + `VideoToolbox`)

    func webcamRequested(pcId: String, options: WebcamOptions) -> Bool {
        WebcamStreamer.shared.start(
            pcId: pcId,
            camera: options.camera,
            maxHeight: max(options.width, options.height),
            fps: options.fps,
            preferHevc: true
        )
    }

    func webcamStopRequested(pcId: String) {
        WebcamStreamer.shared.stop(pcId: pcId)
    }

    func webcamKeyframeRequested(pcId: String) {
        WebcamStreamer.shared.requestKeyframe()
    }

    // MARK: - Phone as PC Microphone (`AVAudioEngine`)

    func micRequested(pcId: String) -> Bool {
        MicStreamer.shared.start(pcId: pcId)
    }

    func micStopRequested(pcId: String) {
        MicStreamer.shared.stop(pcId: pcId)
    }

    // MARK: - Continuity Camera (`photo` & `scan`)

    func cameraCaptureRequested(pcId: String, requestId: String, mode: String) -> Bool {
        ContinuityCameraManager.shared.handleIncomingRequest(
            pcId: pcId,
            requestId: requestId,
            mode: mode
        )
    }

    func cameraCaptureCancelled(pcId: String, requestId: String) {
        if ContinuityCameraManager.shared.activeRequest?.requestId == requestId {
            DispatchQueue.main.async {
                ContinuityCameraManager.shared.activeRequest = nil
            }
        }
    }

    // MARK: - Android-Only Capabilities (Launchable Apps & SMS Database)

    func phoneApps() -> [PhoneApp] {
        []
    }

    func smsThreads(limit: UInt32) -> [SmsThread] {
        []
    }

    func smsMessages(thread: String, before: Int64?, limit: UInt32) -> [SmsMessage] {
        []
    }

    func smsSend(to: [String], body: String) -> Bool {
        // Open native Messages composer via sms: URL if the user is in foreground.
        guard let recipient = to.first, !recipient.isEmpty else { return false }
        var components = URLComponents()
        components.scheme = "sms"
        components.path = recipient
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        guard let url = components.url else { return false }
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        return false
    }

    func sendSmsWithAttachments(to: [String], body: String, attachments: [SmsAttachment]) -> Bool {
        false
    }

    func smsPart(id: String) -> SmsPartData? {
        nil
    }

    // MARK: - Quick Settings Toggles (Flashlight, Brightness, Volume)

    func setPhoneToggle(id: String, value: PhoneToggleValue) -> Bool {
        IosToggles.shared.setPhoneToggle(id: id, value: value)
    }

    // MARK: - Phone File Storage (`Documents/NectarLink` + App Group Shared Container)

    func storageList(path: String) throws -> [StorageEntry] {
        try IosStorage.shared.storageList(path: path)
    }

    func storageOpenRead(path: String) throws -> StorageReadFile {
        try IosStorage.shared.storageOpenRead(path: path)
    }

    func storageWrite(path: String, stagedPath: String, modified: Int64?) throws -> StorageWriteDone {
        try IosStorage.shared.storageWrite(path: path, stagedPath: stagedPath, modified: modified)
    }

    func storageMkdir(path: String) throws {
        try IosStorage.shared.storageMkdir(path: path)
    }

    func storageRename(from: String, to: String) throws {
        try IosStorage.shared.storageRename(from: from, to: to)
    }

    func storageDelete(path: String, confirmed: Bool) throws {
        try IosStorage.shared.storageDelete(path: path, confirmed: confirmed)
    }
}
