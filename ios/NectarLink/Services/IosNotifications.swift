// SPDX-License-Identifier: MPL-2.0

import Foundation
import UIKit
import UserNotifications

/// Delivers local notifications on iOS when a paired PC shares links, Watch
/// offers, task notifications (`task.notify`), or Continuity Camera prompts.
public final class IosNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = IosNotifications()

    public var onStopRingingRequested: (@Sendable () -> Void)?
    public var onOpenUrlRequested: (@Sendable (URL) -> Void)?

    private override init() {
        super.init()
    }

    public func configureCategories() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let stopAction = UNNotificationAction(
            identifier: Ringer.stopNotificationActionId,
            title: "Stop Ringing",
            options: [.foreground]
        )
        let ringCategory = UNNotificationCategory(
            identifier: Ringer.notificationCategoryId,
            actions: [stopAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([ringCategory])
    }

    public func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func handleOpenLink(fromId: String, urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                let content = UNMutableNotificationContent()
                content.title = "Link from your PC"
                content.body = urlString
                content.sound = .default
                content.userInfo = ["url": urlString, "fromId": fromId]

                let req = UNNotificationRequest(
                    identifier: "link-\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(req)
            }
        }
        return true
    }

    public func postTaskNotification(fromId: String, task: TaskNotify) -> Bool {
        let content = UNMutableNotificationContent()
        let seconds = max(1, Int(task.elapsedMs / 1000))
        if task.active {
            content.title = "Running on PC: \(task.title)"
            content.body = "Elapsed: \(seconds)s"
        } else if let code = task.exitCode, code != 0 {
            content.title = "Task failed (\(code)): \(task.title)"
            content.body = "Finished in \(seconds)s"
            content.sound = .default
        } else {
            content.title = "Task finished: \(task.title)"
            content.body = "Completed in \(seconds)s"
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "task-\(fromId)-\(task.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        return true
    }

    public func postWatchOfferNotification(fromId: String, player: String, title: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Continue watching on iPhone"
        content.body = title ?? player
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "watch-\(fromId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func postCameraCaptureNotification(mode: String) {
        let content = UNMutableNotificationContent()
        content.title = mode == "scan" ? "Scan document for PC" : "Take photo for PC"
        content.body = "Tap to open the camera and send directly to your PC."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "continuity-camera",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == Ringer.stopNotificationActionId
            || response.notification.request.identifier == "nectarlink-ringing" {
            Ringer.shared.stop()
            onStopRingingRequested?()
            return
        }

        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            await MainActor.run {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}
