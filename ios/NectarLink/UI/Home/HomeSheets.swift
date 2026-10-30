import SwiftUI
import UIKit
import VisionKit

// MARK: - Clipboard History Sheet

struct ClipboardHistorySheet: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.surface.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        Toggle(
                            "Save Clipboard History (Encrypted)",
                            isOn: Binding(
                                get: { store.state.clipboardHistoryEnabled },
                                set: { store.setClipboardHistoryEnabled($0) }
                            )
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.onSurface)
                        .tint(palette.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.onSurfaceVariant)
                        TextField("Search clips…", text: $query)
                            .foregroundStyle(palette.onSurface)
                            .onChange(of: query) { newValue in
                                store.searchClipboardHistory(query: newValue)
                            }
                        if !query.isEmpty {
                            Button {
                                query = ""
                                store.searchClipboardHistory(query: nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                    }
                    .padding(10)
                    .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    if store.state.clipboardHistory.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 40))
                                .foregroundStyle(palette.onSurfaceVariant)
                            Text("No clipboard items yet")
                                .font(.subheadline)
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(store.state.clipboardHistory, id: \.id) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        if item.pinned {
                                            Image(systemName: "pin.fill")
                                                .font(.caption)
                                                .foregroundStyle(palette.primary)
                                        }
                                        Text(item.deviceName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(palette.primary)
                                        Spacer()
                                        Text(Date(timeIntervalSince1970: TimeInterval(item.timestamp)), style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(palette.onSurfaceVariant)
                                    }

                                    if item.kind == .image {
                                        Label("Clipboard Image (\(item.mime ?? "image/png"))", systemImage: "photo")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(palette.onSurface)
                                    } else {
                                        Text(item.text)
                                            .font(.subheadline)
                                            .lineLimit(3)
                                            .foregroundStyle(palette.onSurface)
                                    }

                                    HStack(spacing: 14) {
                                        Button {
                                            store.copyClipToPhone(id: item.id)
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                                .font(.caption.weight(.semibold))
                                        }

                                        if let pc = store.activePc {
                                            Button {
                                                store.resendClip(id: item.id, to: pc.id)
                                            } label: {
                                                Label("Send to \(pc.info.name)", systemImage: "paperplane")
                                                    .font(.caption.weight(.semibold))
                                            }
                                        }

                                        Button {
                                            store.pinClip(id: item.id, pinned: !item.pinned)
                                        } label: {
                                            Image(systemName: item.pinned ? "pin.slash" : "pin")
                                                .font(.caption)
                                        }

                                        Spacer()

                                        Button(role: .destructive) {
                                            store.deleteClip(id: item.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(palette.primary)
                                    .padding(.top, 4)
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(palette.surfaceContainer)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Clipboard History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !store.state.clipboardHistory.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear All", role: .destructive) {
                            store.clearClipboardHistory()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Cross-Device Timeline Sheet

struct TimelineSheet: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var selectedKind: TimelineKind?

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.surface.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.onSurfaceVariant)
                        TextField("Search activity…", text: $search)
                            .foregroundStyle(palette.onSurface)
                            .onChange(of: search) { _ in
                                store.queryTimeline(kind: selectedKind, search: search)
                            }
                    }
                    .padding(10)
                    .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(title: "All", kind: nil)
                            filterChip(title: "Files", kind: .file)
                            filterChip(title: "Clipboard", kind: .clip)
                            filterChip(title: "Links", kind: .link)
                            filterChip(title: "Photos", kind: .photo)
                            filterChip(title: "Voice", kind: .recording)
                        }
                        .padding(.horizontal, 16)
                    }

                    if store.state.timelineEntries.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 40))
                                .foregroundStyle(palette.onSurfaceVariant)
                            Text("No timeline activity found")
                                .font(.subheadline)
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(store.state.timelineEntries, id: \.id) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: iconForTimelineKind(entry.kind))
                                        .font(.title3)
                                        .foregroundStyle(palette.primary)
                                        .frame(width: 30)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(entry.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(palette.onSurface)
                                            Spacer()
                                            Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)), style: .relative)
                                                .font(.caption2)
                                                .foregroundStyle(palette.onSurfaceVariant)
                                        }
                                        if !entry.detail.isEmpty {
                                            Text(entry.detail)
                                                .font(.caption)
                                                .foregroundStyle(palette.onSurfaceVariant)
                                                .lineLimit(2)
                                        }
                                        Text("\(entry.deviceName) • \(entry.incoming ? "Received" : "Sent")")
                                            .font(.caption2)
                                            .foregroundStyle(palette.outline)
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.deleteTimelineEntry(id: entry.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowBackground(palette.surfaceContainer)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !store.state.timelineEntries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) {
                            store.clearTimeline()
                        }
                    }
                }
            }
            .onAppear {
                store.queryTimeline(kind: selectedKind, search: search)
            }
        }
    }

    private func filterChip(title: String, kind: TimelineKind?) -> some View {
        let active = selectedKind == kind
        return Button {
            selectedKind = kind
            store.queryTimeline(kind: kind, search: search)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? palette.primary : palette.surfaceContainerHigh, in: Capsule())
                .foregroundStyle(active ? palette.onPrimary : palette.onSurface)
        }
    }

    private func iconForTimelineKind(_ kind: TimelineKind) -> String {
        switch kind {
        case .file: return "doc.fill"
        case .clip: return "doc.on.clipboard"
        case .link: return "safari.fill"
        case .photo: return "photo.fill"
        case .recording: return "waveform"
        case .session: return "link.circle.fill"
        }
    }
}

// MARK: - Remote PC File Browser Sheet

struct RemotePcFilesSheet: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    let pc: PairedDevice
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dismiss) private var dismiss

    @State private var currentPath = ""
    @State private var entries: [RemoteStorageEntry] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var downloadedFileUrl: URL?

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        if !currentPath.isEmpty {
                            Button {
                                navigateUp()
                            } label: {
                                Label("Up", systemImage: "chevron.left")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        Text(currentPath.isEmpty ? "PC Shared Root" : currentPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(palette.onSurfaceVariant)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            loadDirectory(path: currentPath)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(palette.surfaceContainerLow)

                    if loading {
                        Spacer()
                        ProgressView("Loading \(pc.info.name) files…")
                            .tint(palette.primary)
                        Spacer()
                    } else if let errorMessage {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 40))
                                .foregroundStyle(palette.primary)
                            Text(errorMessage)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(palette.onSurfaceVariant)
                                .padding(.horizontal, 24)
                        }
                        Spacer()
                    } else if entries.isEmpty {
                        Spacer()
                        Text("This folder is empty")
                            .font(.subheadline)
                            .foregroundStyle(palette.onSurfaceVariant)
                        Spacer()
                    } else {
                        List(entries, id: \.path) { entry in
                            Button {
                                if entry.kind == "dir" {
                                    loadDirectory(path: entry.path)
                                } else {
                                    downloadEntry(entry)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: entry.kind == "dir" ? "folder.fill" : "doc.fill")
                                        .foregroundStyle(entry.kind == "dir" ? palette.primary : palette.onSurfaceVariant)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(palette.onSurface)
                                        if entry.kind != "dir" {
                                            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                                                .font(.caption2)
                                                .foregroundStyle(palette.onSurfaceVariant)
                                        }
                                    }
                                    Spacer()
                                    if entry.kind == "dir" {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(palette.onSurfaceVariant)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                            .foregroundStyle(palette.primary)
                                    }
                                }
                            }
                            .listRowBackground(palette.surfaceContainer)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("\(pc.info.name) Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                loadDirectory(path: "")
            }
            .sheet(item: Binding(
                get: { downloadedFileUrl.map { IdentifiableUrl(url: $0) } },
                set: { if $0 == nil { downloadedFileUrl = nil } }
            )) { item in
                ShareActivityView(items: [item.url])
            }
        }
    }

    private func navigateUp() {
        let parts = currentPath.split(separator: "/").dropLast()
        loadDirectory(path: parts.joined(separator: "/"))
    }

    private func loadDirectory(path: String) {
        loading = true
        errorMessage = nil
        Task {
            do {
                let items = try await store.listRemoteStorage(peerId: pc.id, path: path)
                self.currentPath = path
                self.entries = items
                self.loading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.loading = false
            }
        }
    }

    private func downloadEntry(_ entry: RemoteStorageEntry) {
        loading = true
        Task {
            let localUrl = await store.downloadRemoteStorage(
                peerId: pc.id,
                remotePath: entry.path,
                fileName: entry.name
            )
            self.loading = false
            if let localUrl {
                self.downloadedFileUrl = localUrl
            } else {
                store.showToast("Failed to download \(entry.name)")
            }
        }
    }
}

private struct IdentifiableUrl: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Continuity Camera Capture Sheet (Camera & VisionKit Document Scanner)

struct ContinuityCameraSheet: UIViewControllerRepresentable {
    let request: ContinuityCameraManager.CaptureRequest

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        if request.mode == "scan" && VNDocumentCameraViewController.isSupported {
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = context.coordinator
            return scanner
        } else {
            let picker = UIImagePickerController()
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                picker.sourceType = .camera
            } else {
                picker.sourceType = .photoLibrary
            }
            picker.delegate = context.coordinator
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, VNDocumentCameraViewControllerDelegate {
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                ContinuityCameraManager.shared.completeCapture(image: image)
            } else {
                ContinuityCameraManager.shared.cancelActiveRequest()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            ContinuityCameraManager.shared.cancelActiveRequest()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                ContinuityCameraManager.shared.cancelActiveRequest()
                return
            }
            let firstPage = scan.imageOfPage(at: 0)
            ContinuityCameraManager.shared.completeCapture(image: firstPage)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            ContinuityCameraManager.shared.cancelActiveRequest()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            ContinuityCameraManager.shared.cancelActiveRequest(reason: error.localizedDescription)
        }
    }
}
