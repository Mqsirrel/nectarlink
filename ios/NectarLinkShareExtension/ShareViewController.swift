import Social
import UIKit
import UniformTypeIdentifiers

/// System Share Sheet extension that stages shared files, photos, videos, URLs, and text
/// into the `group.app.nectarlink` App Group inbox and hands off to NectarLink to send to the PC.
final class ShareViewController: UIViewController {
    private static let appGroupIdentifier = "group.app.nectarlink"

    private struct InboxItem: Codable {
        let kind: String // "file", "url", "text"
        let value: String?
    }

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCardUI()
        Task {
            await processSharedItems()
        }
    }

    private func setupCardUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.96)
        card.layer.cornerRadius = 22
        view.addSubview(card)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = UIColor(red: 1.0, green: 0.73, blue: 0.37, alpha: 1.0)
        spinner.startAnimating()
        card.addSubview(spinner)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Sending to PC via NectarLink…"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textAlignment = .center
        card.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 270),
            card.heightAnchor.constraint(equalToConstant: 140),

            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
    }

    private func processSharedItems() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem],
              let container = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
              ) else {
            finishExtension()
            return
        }

        let inboxDir = container.appendingPathComponent("ShareInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        var staged: [InboxItem] = []

        for item in extensionItems {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = await loadUrl(from: provider, typeId: UTType.fileURL.identifier),
                       let savedName = copyFileToInbox(sourceUrl: url, inboxDir: inboxDir) {
                        staged.append(InboxItem(kind: "file", value: savedName))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let savedName = await loadAndSaveData(from: provider, typeId: UTType.image.identifier, defaultExt: "jpg", inboxDir: inboxDir) {
                        staged.append(InboxItem(kind: "file", value: savedName))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    if let savedName = await loadAndSaveData(from: provider, typeId: UTType.movie.identifier, defaultExt: "mp4", inboxDir: inboxDir) {
                        staged.append(InboxItem(kind: "file", value: savedName))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadUrl(from: provider, typeId: UTType.url.identifier) {
                        if url.isFileURL, let savedName = copyFileToInbox(sourceUrl: url, inboxDir: inboxDir) {
                            staged.append(InboxItem(kind: "file", value: savedName))
                        } else {
                            staged.append(InboxItem(kind: "url", value: url.absoluteString))
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider) {
                        staged.append(InboxItem(kind: "text", value: text))
                    }
                }
            }
        }

        if !staged.isEmpty, let json = try? JSONEncoder().encode(staged) {
            let manifestUrl = inboxDir.appendingPathComponent("manifest.json")
            try? json.write(to: manifestUrl, options: .atomic)
        }

        await MainActor.run {
            openContainingApp()
            finishExtension()
        }
    }

    private func copyFileToInbox(sourceUrl: URL, inboxDir: URL) -> String? {
        let accessed = sourceUrl.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceUrl.stopAccessingSecurityScopedResource() }
        }
        let baseName = sourceUrl.lastPathComponent.isEmpty ? "SharedFile" : sourceUrl.lastPathComponent
        let destName = "\(Int(Date().timeIntervalSince1970))_\(baseName)"
        let destUrl = inboxDir.appendingPathComponent(destName)
        do {
            try FileManager.default.copyItem(at: sourceUrl, to: destUrl)
            return destName
        } catch {
            return nil
        }
    }

    private func loadUrl(from provider: NSItemProvider, typeId: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadAndSaveData(
        from provider: NSItemProvider,
        typeId: String,
        defaultExt: String,
        inboxDir: URL
    ) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                if let url = item as? URL,
                   let saved = self.copyFileToInbox(sourceUrl: url, inboxDir: inboxDir) {
                    continuation.resume(returning: saved)
                    return
                }
                if let image = item as? UIImage,
                   let jpeg = image.jpegData(compressionQuality: 0.90) {
                    let name = "Shared_\(UUID().uuidString.prefix(8)).jpg"
                    let dest = inboxDir.appendingPathComponent(name)
                    if (try? jpeg.write(to: dest)) != nil {
                        continuation.resume(returning: name)
                        return
                    }
                }
                if let data = item as? Data {
                    let name = "Shared_\(UUID().uuidString.prefix(8)).\(defaultExt)"
                    let dest = inboxDir.appendingPathComponent(name)
                    if (try? data.write(to: dest)) != nil {
                        continuation.resume(returning: name)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    @MainActor
    private func openContainingApp() {
        guard let url = URL(string: "nectarlink://share") else { return }
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                break
            }
            responder = current.next
        }
    }

    @MainActor
    private func finishExtension() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
