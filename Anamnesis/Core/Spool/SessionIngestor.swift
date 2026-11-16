import AnamnesisKit
import Foundation
import Observation

/// One spool session as the UI sees it.
nonisolated struct SpoolSessionSummary: Sendable, Identifiable {
    var id: String { session.id }
    let session: SpoolSession
    /// nil if the manifest is missing or unreadable (recovery will rebuild it unless the session is active).
    let manifest: SpoolManifest?
    #if DEBUG
    /// Only the Lab shows it; sizing every folder on every refresh is not worth it in Release (review follow-up 3).
    let sizeBytes: Int
    #endif
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
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    /// Set when a refresh is asked for while one runs: that one scans again before it ends.
    @ObservationIgnored private var rescanExcluding: Set<String>?

    init(directory: SpoolDirectory, log: AppLog) {
        self.directory = directory
        self.log = log
    }

    /// `activeSessionIDs` are being written right now and must not be "recovered" under the writer.
    ///
    /// A call made while a scan runs waits for a fresh scan rather than returning at once: a capture that stopped
    /// mid-scan was otherwise missed until the next foreground, so it got no row and was not transcribed (review B4).
    func refresh(activeSessionIDs: Set<String>) async {
        if let inFlight {
            // Excluding more is safe: a session left out is only recovered on a later pass.
            rescanExcluding = (rescanExcluding ?? []).union(activeSessionIDs)
            await inFlight.value
            return
        }
        let task = Task {
            var excluded = activeSessionIDs
            while true {
                await scan(excluding: excluded)
                // Checked and cleared on the main actor in one step, so a request can never fall between them.
                guard let next = rescanExcluding else { break }
                rescanExcluding = nil
                excluded = next
            }
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func scan(excluding activeSessionIDs: Set<String>) async {
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
        let manifest = try? SpoolManifest.read(from: session.manifestURL)
        #if DEBUG
        return SpoolSessionSummary(
            session: session, manifest: manifest, sizeBytes: session.sizeOnDisk(), isDone: session.isDone,
            hasAudio: session.hasAudio, hasTranscript: session.hasTranscript)
        #else
        return SpoolSessionSummary(
            session: session, manifest: manifest, isDone: session.isDone, hasAudio: session.hasAudio,
            hasTranscript: session.hasTranscript)
        #endif
    }
}
