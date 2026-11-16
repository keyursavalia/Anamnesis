import Foundation

extension SpoolDirectory {
    /// Removes a session folder and everything in it. Refuses paths outside this root.
    public func delete(_ session: SpoolSession) throws {
        let parent = session.directory.deletingLastPathComponent().standardizedFileURL
        guard parent == root.standardizedFileURL else { throw SpoolError.fileFailed("not in spool root") }
        try FileManager.default.removeItem(at: session.directory)
    }
}

extension SpoolSession {
    /// D-010 after a successful transcription (spec 008 R7): removes the audio segments only, so the manifest,
    /// `DONE`, `capture.json` and `transcript.json` stay. Returns the number of files removed.
    @discardableResult
    public func deleteAudio() throws -> Int {
        let files = segmentFiles()
        for file in files { try FileManager.default.removeItem(at: file.url) }
        return files.count
    }
}
