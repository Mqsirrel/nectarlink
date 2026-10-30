// SPDX-License-Identifier: MPL-2.0

import Foundation
import Photos
import UIKit

/// Bridges `PHPhotoLibrary` for the PC Photos browser (`photoAlbums`, `photoList`,
/// `photoThumbs`, `openPhoto`) and observes newly taken photos/screenshots.
public final class IosPhotos: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    public static let shared = IosPhotos()

    public var onPhotoTaken: (@Sendable (Photo) -> Void)?
    public var onPhotosChanged: (@Sendable () -> Void)?

    private let imageManager = PHCachingImageManager()
    private let lock = NSLock()
    private var observing = false
    private var lastSeenAssetId: String?
    private var lastNotifiedAt: Date = .distantPast

    private override init() {
        super.init()
    }

    public static var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    public func startObservingIfAuthorized() {
        guard Self.isAuthorized else { return }
        lock.lock()
        if observing {
            lock.unlock()
            return
        }
        observing = true
        lock.unlock()

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        let latest = PHAsset.fetchAssets(with: fetchOptions).firstObject
        lock.lock()
        lastSeenAssetId = latest?.localIdentifier
        lock.unlock()

        PHPhotoLibrary.shared().register(self)
    }

    public func stopObserving() {
        lock.lock()
        let wasObserving = observing
        observing = false
        lock.unlock()
        if wasObserving {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        onPhotosChanged?()

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: fetchOptions).firstObject else {
            return
        }

        lock.lock()
        let previousId = lastSeenAssetId
        lastSeenAssetId = asset.localIdentifier
        lock.unlock()

        guard asset.localIdentifier != previousId else { return }
        if let created = asset.creationDate, Date().timeIntervalSince(created) <= 30 {
            if let photo = buildInstantPhotoNotification(for: asset) {
                onPhotoTaken?(photo)
            }
        }
    }

    /// Lists albums for a paired PC, placing Recents/Camera and Screenshots first.
    public func photoAlbums() -> [PhotoAlbum] {
        guard Self.isAuthorized else { return [] }

        var results: [PhotoAlbum] = []
        var seenIds = Set<String>()

        let smartSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumUserLibrary,
            .smartAlbumScreenshots,
            .smartAlbumFavorites,
            .smartAlbumVideos,
        ]

        for subtype in smartSubtypes {
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            collections.enumerateObjects { collection, _, _ in
                if let album = Self.makeAlbum(from: collection), seenIds.insert(album.id).inserted {
                    results.append(album)
                }
            }
        }

        let userCollections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var userAlbums: [PhotoAlbum] = []
        userCollections.enumerateObjects { collection, _, _ in
            if let album = Self.makeAlbum(from: collection), seenIds.insert(album.id).inserted {
                userAlbums.append(album)
            }
        }
        userAlbums.sort { $0.count > $1.count }
        results.append(contentsOf: userAlbums)
        return results
    }

    /// Lists photos and videos newest first, with cursor pagination (`before`, `beforeId`).
    public func photoList(album: String?, before: Int64?, beforeId: String, limit: UInt32) -> [PhotoItem] {
        guard Self.isAuthorized else { return [] }
        let maxCount = Int(max(1, min(limit, 200)))

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let before {
            let cutoffDate = Date(timeIntervalSince1970: TimeInterval(before) / 1000.0)
            options.predicate = NSPredicate(format: "creationDate <= %@", cutoffDate as NSDate)
        }

        let assets: PHFetchResult<PHAsset>
        if let album, !album.isEmpty,
           let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album], options: nil).firstObject {
            assets = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: options)
        }

        var items: [PhotoItem] = []
        items.reserveCapacity(maxCount)

        assets.enumerateObjects { asset, _, stop in
            guard asset.mediaType == .image || asset.mediaType == .video else { return }
            let dateMs = Int64((asset.creationDate ?? .distantPast).timeIntervalSince1970 * 1000.0)
            if let before {
                if dateMs > before { return }
                if dateMs == before && (beforeId.isEmpty || asset.localIdentifier >= beforeId) {
                    return
                }
            }

            let resources = PHAssetResource.assetResources(for: asset)
            let primaryResource = resources.first
            let filename = primaryResource?.originalFilename ?? "IMG_\(asset.localIdentifier.prefix(8)).jpg"
            let fileSize = (primaryResource?.value(forKey: "fileSize") as? CLong).map { UInt64(max(0, $0)) } ?? 0
            let durationMs: UInt32? = asset.mediaType == .video ? UInt32(max(0, Int(asset.duration * 1000.0))) : nil

            items.append(
                PhotoItem(
                    id: asset.localIdentifier,
                    name: filename,
                    date: dateMs,
                    size: fileSize,
                    width: UInt32(asset.pixelWidth),
                    height: UInt32(asset.pixelHeight),
                    duration: durationMs,
                    album: album
                )
            )
            if items.count >= maxCount {
                stop.pointee = true
            }
        }
        return items
    }

    /// Generates compact JPEG thumbnails (<= 32 KiB, ~256 px) for the requested asset IDs.
    public func photoThumbs(ids: [String]) -> [PhotoThumb] {
        guard Self.isAuthorized, !ids.isEmpty else { return [] }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var out: [PhotoThumb] = []

        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = true
        reqOptions.deliveryMode = .fastFormat
        reqOptions.resizeMode = .fast
        reqOptions.isNetworkAccessAllowed = false

        fetched.enumerateObjects { asset, _, _ in
            var thumbData: Data?
            self.imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 256, height: 256),
                contentMode: .aspectFit,
                options: reqOptions
            ) { image, _ in
                guard let image else { return }
                thumbData = Self.compressJpeg(image, maxBytes: 32 * 1024)
            }
            if let thumbData {
                out.append(PhotoThumb(id: asset.localIdentifier, data: thumbData))
            }
        }
        return out
    }

    /// Exports a full-resolution photo or video to a temporary file and returns `FileToSend.path`.
    public func openPhoto(id: String) -> FileToSend? {
        guard Self.isAuthorized else { return nil }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }) ?? resources.first else {
            return nil
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nectarlink-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safeName = (resource.originalFilename as NSString).lastPathComponent
        let fileName = safeName.isEmpty ? "photo-\(UUID().uuidString.prefix(8)).jpg" : safeName
        let destURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(fileName)")

        let semaphore = DispatchSemaphore(value: 0)
        let reqOptions = PHAssetResourceRequestOptions()
        reqOptions.isNetworkAccessAllowed = true
        var writeError: Error?

        PHAssetResourceManager.default().writeData(for: resource, toFile: destURL, options: reqOptions) { error in
            writeError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)

        guard writeError == nil, FileManager.default.fileExists(atPath: destURL.path) else {
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }
        return .path(name: fileName, path: destURL.path, folder: nil)
    }

    private func buildInstantPhotoNotification(for asset: PHAsset) -> Photo? {
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = true
        reqOptions.deliveryMode = .highQualityFormat
        reqOptions.resizeMode = .fast
        reqOptions.isNetworkAccessAllowed = false

        var thumbData: Data?
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 512, height: 512),
            contentMode: .aspectFit,
            options: reqOptions
        ) { image, _ in
            guard let image else { return }
            thumbData = Self.compressJpeg(image, maxBytes: 96 * 1024)
        }
        guard let thumbData else { return nil }

        let resources = PHAssetResource.assetResources(for: asset)
        let resource = resources.first
        let name = resource?.originalFilename ?? "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
        let size = (resource?.value(forKey: "fileSize") as? CLong).map { UInt64(max(0, $0)) } ?? UInt64(thumbData.count)
        let taken = Int64((asset.creationDate ?? Date()).timeIntervalSince1970)
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)

        return Photo(
            id: asset.localIdentifier,
            name: name,
            size: size,
            taken: taken,
            screenshot: isScreenshot,
            thumb: thumbData
        )
    }

    private static func makeAlbum(from collection: PHAssetCollection) -> PhotoAlbum? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        guard assets.count > 0 else { return nil }
        let newestId = assets.firstObject?.localIdentifier
        let title = collection.localizedTitle ?? "Photos"
        return PhotoAlbum(
            id: collection.localIdentifier,
            name: title,
            count: UInt32(assets.count),
            cover: newestId
        )
    }

    public static func compressJpeg(_ image: UIImage, maxBytes: Int) -> Data? {
        var quality: CGFloat = 0.82
        while quality >= 0.25 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.15
        }
        return image.jpegData(compressionQuality: 0.2)
    }
}
