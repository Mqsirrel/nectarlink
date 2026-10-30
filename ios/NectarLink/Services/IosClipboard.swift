// SPDX-License-Identifier: MPL-2.0

import Foundation
import UIKit
import UniformTypeIdentifiers

public enum OutgoingClipboardPayload: Sendable {
    case text(text: String, html: String?, rtf: String?)
    case image(mime: String, data: Data)
}

/// Bridges `UIPasteboard.general` with echo suppression so clips written by a
/// paired PC are not immediately re-broadcast back to the PC.
public final class IosClipboard: @unchecked Sendable {
    public static let shared = IosClipboard()

    private let lock = NSLock()
    private var lastCoreWriteTime: TimeInterval = 0
    private var lastObservedChangeCount: Int = -1

    private init() {}

    public func setText(_ text: String) -> Bool {
        setRichText(text: text, html: nil, rtf: nil)
    }

    public func setRichText(text: String, html: String?, rtf: String?) -> Bool {
        guard !text.isEmpty else { return false }
        let applyBlock = {
            var item: [String: Any] = [
                UTType.utf8PlainText.identifier: text,
            ]
            if let html, !html.isEmpty {
                item[UTType.html.identifier] = html
            }
            if let rtf, !rtf.isEmpty, let rtfData = rtf.data(using: .utf8) {
                item[UTType.rtf.identifier] = rtfData
            }
            UIPasteboard.general.setItems([item], options: [:])
            self.recordCoreWrite(changeCount: UIPasteboard.general.changeCount)
        }

        if Thread.isMainThread {
            applyBlock()
        } else {
            DispatchQueue.main.sync(execute: applyBlock)
        }
        return true
    }

    public func setImage(mime: String, bytes: Data) -> Bool {
        guard !bytes.isEmpty, let image = UIImage(data: bytes) else { return false }
        let applyBlock = {
            UIPasteboard.general.image = image
            self.recordCoreWrite(changeCount: UIPasteboard.general.changeCount)
        }
        if Thread.isMainThread {
            applyBlock()
        } else {
            DispatchQueue.main.sync(execute: applyBlock)
        }
        return true
    }

    /// Reads the current pasteboard for manual "Send Clipboard" or foreground sync.
    @MainActor
    public func readCurrentPayload(onlyIfChanged: Bool = false) -> OutgoingClipboardPayload? {
        let pb = UIPasteboard.general
        let count = pb.changeCount

        lock.lock()
        let isEcho = (Date().timeIntervalSince1970 - lastCoreWriteTime) < 2.0 || count == lastObservedChangeCount
        if onlyIfChanged && isEcho {
            lock.unlock()
            return nil
        }
        lastObservedChangeCount = count
        lock.unlock()

        if pb.hasImages, let image = pb.image {
            if let png = image.pngData(), png.count <= 20 * 1024 * 1024 {
                return .image(mime: "image/png", data: png)
            }
            if let jpeg = image.jpegData(compressionQuality: 0.9) {
                return .image(mime: "image/jpeg", data: jpeg)
            }
        }

        if pb.hasStrings, let str = pb.string, !str.isEmpty {
            var html: String? = nil
            var rtf: String? = nil
            if let htmlData = pb.data(forPasteboardType: UTType.html.identifier),
               let decoded = String(data: htmlData, encoding: .utf8) {
                html = decoded
            }
            if let rtfData = pb.data(forPasteboardType: UTType.rtf.identifier),
               let decoded = String(data: rtfData, encoding: .utf8) {
                rtf = decoded
            }
            return .text(text: str, html: html, rtf: rtf)
        }

        return nil
    }

    private func recordCoreWrite(changeCount: Int) {
        lock.lock()
        lastCoreWriteTime = Date().timeIntervalSince1970
        lastObservedChangeCount = changeCount
        lock.unlock()
    }
}
