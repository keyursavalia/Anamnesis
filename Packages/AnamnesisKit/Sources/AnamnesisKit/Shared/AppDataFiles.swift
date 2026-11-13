import Foundation

/// The app's files on disk, for the Settings storage figures and *Delete all data* (spec 013 R2, R3).
public enum AppDataFiles {
    public struct Entry: Sendable, Equatable {
        /// Relative to the listed root, `/`-separated.
        public var path: String
        public var bytes: Int64
    }

    /// Total size of the files under `url` (or of `url` itself); 0 when missing.
    public static func size(of url: URL) -> Int64 {
        let ownSize = fileSize(url)
        guard isDirectory(url) else { return ownSize }
        return files(under: url).reduce(0) { $0 + $1.bytes }
    }

    /// Every regular file under `root`, sorted by path. Hidden files are included: nothing may hide from AC1.
    public static func files(under root: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return []
        }
        let base = root.standardizedFileURL.pathComponents.count
        var entries: [Entry] = []
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let parts = url.standardizedFileURL.pathComponents.dropFirst(base)
            entries.append(Entry(path: parts.joined(separator: "/"), bytes: fileSize(url)))
        }
        return entries.sorted { $0.path < $1.path }
    }

    /// Deletes everything inside `url` and keeps the folder itself. Missing folder: nothing to do.
    public static func removeContents(of url: URL) throws {
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for child in children { try FileManager.default.removeItem(at: child) }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
