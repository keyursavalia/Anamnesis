import AnamnesisKit
import Foundation
import Observation

/// One spool session as the UI sees it.
nonisolated struct SpoolSessionSummary: Sendable, Identifiable {
    var id: String { session.id }
    let session: SpoolSession
    /// nil if the manifest is missing or unreadable (recovery will rebuild it unless the session is active).
    let manifest: SpoolManifest?
    let sizeBytes: Int
    let isDone: Bool
    /// Segments still on disk; false once D-010 has deleted them after a transcription (spec 008 R7).
    let hasAudio: Bool
    let hasTranscript: Bool
}

/// Scans the spool root at launch and on foreground (spec 002 Step 6): recovers sessions the app died in,
/// then lists everything for the Lab (and, later, the library ingest).
@Observable
final class SessionIngestor {
    /// Newest first.
    private(set) var sessions: [SpoolSessionSummary] = []
    private(set) var lastRecovery: [SpoolRecovery.Result] = []

    let directory: SpoolDirectory
    private let log: AppLog
    private var isRefreshing = false

    init(directory: SpoolDirectory, log: AppLog) {
        self.directory = directory
        self.log = log
    }

    /// `activeSessionIDs` are being written right now and must not be "recovered" under the writer.
    func refresh(activeSessionIDs: Set<String>) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let directory = directory
        let (results, summaries) = await Task.detached {
            let results = SpoolRecovery.recoverAll(in: directory, excluding: activeSessionIDs)
            return (results, directory.sessions().reversed().map(Self.summary))
        }.value
        for result in results {
            log.notice("spool recovered session=\(result.sessionID) state=\(result.state.rawValue) "
                       + "frames=\(result.frames) discarded=\(result.discardedFiles) "
                       + "manifestMissing=\(result.manifestWasMissing)")
        }
        if !results.isEmpty { lastRecovery = results }
        sessions = summaries
    }

    func delete(_ summary: SpoolSessionSummary) throws {
        try directory.delete(summary.session)
        log.notice("spool deleted session=\(summary.id)")
        sessions.removeAll { $0.id == summary.id }
    }

    private nonisolated static func summary(_ session: SpoolSession) -> SpoolSessionSummary {
        SpoolSessionSummary(
            session: session, manifest: try? SpoolManifest.read(from: session.manifestURL),
            sizeBytes: session.sizeOnDisk(), isDone: session.isDone, hasAudio: session.hasAudio,
            hasTranscript: session.hasTranscript)
    }
}
