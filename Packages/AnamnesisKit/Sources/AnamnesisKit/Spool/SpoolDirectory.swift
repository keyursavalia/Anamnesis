import Foundation

/// Root that holds one folder per spool session (ARCHITECTURE §4.3). Only the host-app root exists: there is
/// no extension, so no App Group root (D-017).
public struct SpoolDirectory: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/Spool`.
    public static func appDefault() throws -> SpoolDirectory {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return SpoolDirectory(root: support.appending(path: "Spool"))
    }

    /// Creates `<root>/<id>/`, excluded from backup and protected until first unlock (spec 002 R7).
    /// Files created inside inherit the folder's protection class on iOS.
    public func makeSession(id: String) throws -> SpoolSession {
        var directory = root.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: Self.protectionAttributes)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return SpoolSession(directory: directory)
    }

    /// Every session folder, oldest first (ids sort by time).
    public func sessions() -> [SpoolSession] {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return directories
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(SpoolSession.init(directory:))
    }

    /// e.g. `20261109T171503Z-3fa2`: UTC, sortable, filename-safe; the suffix separates same-second sessions.
    public static func makeSessionID(createdAt: Date, suffix: String = String(UUID().uuidString.prefix(4))) -> String {
        let stamp = createdAt.formatted(
            .iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false)
                .timeSeparator(.omitted))
        // The ISO style is UTC but drops the "Z" once components are picked.
        return "\(stamp)Z-\(suffix.lowercased())"
    }

    private static var protectionAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        [:]
        #endif
    }
}

/// Paths inside one session folder.
public struct SpoolSession: Sendable, Equatable {
    public static let manifestFileName = "manifest.json"
    /// Written only after the last segment is closed and the manifest is final (spec 002 R5).
    public static let doneFileName = "DONE"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var id: String { directory.lastPathComponent }
    public var manifestURL: URL { directory.appending(path: Self.manifestFileName) }
    public var doneURL: URL { directory.appending(path: Self.doneFileName) }
    public var isDone: Bool { FileManager.default.fileExists(atPath: doneURL.path(percentEncoded: false)) }

    public func segmentURL(_ index: Int) -> URL {
        directory.appending(path: Self.segmentFileName(index))
    }

    /// Segment files on disk, ordered by index (independent of the manifest, for recovery).
    public func segmentFiles() -> [(index: Int, url: URL)] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.compactMap { url in Self.segmentIndex(fileName: url.lastPathComponent).map { ($0, url) } }
            .sorted { $0.index < $1.index }
    }

    /// Bytes of every file in the session (segments, manifest, marker).
    public func sizeOnDisk() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// `seg-000001.caf`; indexes start at 1.
    public static func segmentFileName(_ index: Int) -> String {
        "seg-" + String(repeating: "0", count: max(0, 6 - String(index).count)) + "\(index).caf"
    }

    public static func segmentIndex(fileName: String) -> Int? {
        guard fileName.hasPrefix("seg-"), fileName.hasSuffix(".caf") else { return nil }
        let digits = fileName.dropFirst(4).dropLast(4)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }
}
