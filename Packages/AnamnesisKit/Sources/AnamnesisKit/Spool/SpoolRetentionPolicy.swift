import Foundation

/// What happens to a session's audio once it has been transcribed (D-010, spec 002 R9).
/// Nothing in this spec deletes automatically; callers decide and call `SpoolDirectory.delete`.
public enum SpoolRetentionPolicy: String, Sendable, Codable, CaseIterable {
    case deleteAfterTranscription
    /// DEBUG builds only: keep audio for listen-back and Test B.
    case keepForDebug

    public static let `default` = SpoolRetentionPolicy.deleteAfterTranscription

    public var deletesAfterTranscription: Bool { self == .deleteAfterTranscription }
}

extension SpoolDirectory {
    /// Removes a session folder and everything in it. Refuses paths outside this root.
    public func delete(_ session: SpoolSession) throws {
        let parent = session.directory.deletingLastPathComponent().standardizedFileURL
        guard parent == root.standardizedFileURL else { throw SpoolError.fileFailed("not in spool root") }
        try FileManager.default.removeItem(at: session.directory)
    }
}
