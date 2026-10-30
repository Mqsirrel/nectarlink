// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Exposes the iPhone's NectarLink Documents folder (visible in the iOS Files
/// app under "On My iPhone -> NectarLink") and any user-bookmarked folders to
/// a paired PC (`storage.list`, `storage.read`, `storage.write`, `storage.mkdir`,
/// `storage.rename`, `storage.delete`).
public final class IosStorage: @unchecked Sendable {
    public static let shared = IosStorage()

    private let fm = FileManager.default
    private let bookmarkKey = "app.nectarlink.ios.storageBookmarks"

    private init() {
        _ = rootDirectoryURL()
    }

    public func rootDirectoryURL() -> URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let sharedDir = docs.appendingPathComponent("Shared", isDirectory: true)
        if !fm.fileExists(atPath: sharedDir.path) {
            try? fm.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        }
        return sharedDir
    }

    /// Resolves a relative protocol path (`""` for root) inside `rootDirectoryURL()`
    /// while rejecting any `..` or symlink escape attempts.
    private func resolveSafePath(_ relativePath: String, allowRoot: Bool = false) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        if trimmed.isEmpty {
            if allowRoot {
                return rootDirectoryURL()
            }
            throw StorageFailure.Invalid(reason: "Path cannot be empty")
        }
        if trimmed.contains("\0") {
            throw StorageFailure.Invalid(reason: "Null byte in path")
        }

        let components = trimmed.split(separator: "/").map(String.init)
        for comp in components {
            if comp == "." || comp == ".." || comp.contains("\\") {
                throw StorageFailure.Invalid(reason: "Invalid path segment: \(comp)")
            }
        }

        let base = rootDirectoryURL().standardizedFileURL
        var target = base
        for comp in components {
            target.appendPathComponent(comp)
        }
        let resolved = target.standardizedFileURL
        let basePrefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard resolved.path == base.path || resolved.path.hasPrefix(basePrefix) else {
            throw StorageFailure.Invalid(reason: "Path escapes storage root")
        }
        return resolved
    }

    public func list(path: String) throws -> [StorageEntry] {
        let dirURL = try resolveSafePath(path, allowRoot: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir) else {
            throw StorageFailure.NotFound
        }
        guard isDir.boolValue else {
            throw StorageFailure.Invalid(reason: "Not a directory")
        }

        let keys: [URLResourceKey] = [
            .nameKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey,
        ]
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw StorageFailure.Failed(reason: error.localizedDescription)
        }

        var entries: [StorageEntry] = []
        entries.reserveCapacity(urls.count)
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.name ?? url.lastPathComponent
            let entryIsDir = values?.isDirectory ?? false
            let size = UInt64(max(0, values?.fileSize ?? 0))
            let mtime = Int64((values?.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000.0)
            entries.append(
                StorageEntry(
                    name: name,
                    size: entryIsDir ? 0 : size,
                    modified: mtime,
                    isDir: entryIsDir
                )
            )
        }

        entries.sort { a, b in
            if a.isDir != b.isDir {
                return a.isDir && !b.isDir
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return entries
    }

    public func openRead(path: String) throws -> StorageReadFile {
        let fileURL = try resolveSafePath(path, allowRoot: false)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
            throw StorageFailure.NotFound
        }
        if isDir.boolValue {
            throw StorageFailure.Invalid(reason: "Cannot read a directory as a file")
        }

        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let mtimeDate = (attrs[.modificationDate] as? Date) ?? Date()
        let modified = Int64(mtimeDate.timeIntervalSince1970 * 1000.0)

        return StorageReadFile(
            source: .path(name: fileURL.lastPathComponent, path: fileURL.path, folder: nil),
            size: size,
            modified: modified
        )
    }

    public func write(path: String, stagedPath: String, modified: Int64?) throws -> StorageWriteDone {
        let destURL = try resolveSafePath(path, allowRoot: false)
        let stagedURL = URL(fileURLWithPath: stagedPath)
        guard fm.fileExists(atPath: stagedURL.path) else {
            throw StorageFailure.NotFound
        }

        let parentDir = destURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: stagedURL, to: destURL)
            if let modified {
                let mtimeDate = Date(timeIntervalSince1970: TimeInterval(modified) / 1000.0)
                try? fm.setAttributes([.modificationDate: mtimeDate], ofItemAtPath: destURL.path)
            }
            let attrs = try fm.attributesOfItem(atPath: destURL.path)
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            let finalDate = (attrs[.modificationDate] as? Date) ?? Date()
            return StorageWriteDone(
                size: size,
                modified: Int64(finalDate.timeIntervalSince1970 * 1000.0)
            )
        } catch {
            throw StorageFailure.Failed(reason: error.localizedDescription)
        }
    }

    public func mkdir(path: String) throws {
        let dirURL = try resolveSafePath(path, allowRoot: false)
        do {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            throw StorageFailure.Failed(reason: error.localizedDescription)
        }
    }

    public func rename(from: String, to: String) throws {
        let srcURL = try resolveSafePath(from, allowRoot: false)
        let dstURL = try resolveSafePath(to, allowRoot: false)
        guard fm.fileExists(atPath: srcURL.path) else {
            throw StorageFailure.NotFound
        }
        do {
            let parentDir = dstURL.deletingLastPathComponent()
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dstURL.path) {
                try fm.removeItem(at: dstURL)
            }
            try fm.moveItem(at: srcURL, to: dstURL)
        } catch {
            throw StorageFailure.Failed(reason: error.localizedDescription)
        }
    }

    public func delete(path: String, confirmed: Bool) throws {
        let targetURL = try resolveSafePath(path, allowRoot: false)
        guard fm.fileExists(atPath: targetURL.path) else {
            throw StorageFailure.NotFound
        }
        do {
            try fm.removeItem(at: targetURL)
        } catch {
            throw StorageFailure.Failed(reason: error.localizedDescription)
        }
    }
}
