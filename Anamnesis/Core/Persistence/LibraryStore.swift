import AnamnesisKit
import Foundation
import SwiftData

/// The library store on disk (spec 009): `Application Support/Library.store`, CloudKit off, backed up by default
/// (R5; text only). If the file cannot be opened the app runs on an in-memory store and says so, rather than crash.
final class LibraryStore {
    let container: ModelContainer
    let importer: LibraryImporter
    /// Shown on the Captures screen when the on-disk store could not be opened.
    let loadError: String?

    init(directory: URL?, log: AppLog) {
        var loadError: String?
        var opened: ModelContainer?
        if let directory {
            do {
                opened = try .library(at: Self.files(in: directory)[0])
            } catch {
                log.error("library store unavailable: \(error.localizedDescription); using memory")
                loadError = "Your library could not be opened; changes this session will not be kept."
            }
        }
        do {
            container = try opened ?? .library(at: nil)
        } catch {
            // An in-memory container fails only if the schema itself is invalid, which the package tests rule out;
            // the app cannot run without one.
            fatalError("in-memory library store failed: \(error)")
        }
        importer = LibraryImporter(modelContainer: container)
        self.loadError = loadError
    }

    /// Brings the store up to date with the spool: new sessions, audio/duration, and any `transcript.json` the
    /// store has not imported yet (sessions transcribed before spec 009, or a crash between write and import).
    func sync(with summaries: [SpoolSessionSummary], log: AppLog) async {
        let importer = importer
        do {
            let imported = try await importer.importedSessionIDs()
            let (snapshots, pending) = await Task.detached {
                (summaries.compactMap(Self.snapshot),
                 summaries.filter { $0.hasTranscript && !imported.contains($0.id) }.compactMap(Self.readTranscript))
            }.value
            let inserted = try await importer.sync(snapshots)
            for (transcript, hasAudio) in pending {
                let outcome = try await importer.importTranscript(transcript, audioDeleted: !hasAudio)
                log.notice("library import session=\(transcript.sessionID) outcome=\(outcome)")
            }
            if inserted > 0 { log.notice("library sessions inserted=\(inserted)") }
        } catch {
            log.error("library sync failed: \(error.localizedDescription)")
        }
    }

    /// *Delete all data* (spec 013 R3): every poem, session and Moment, on the main context so the screens empty
    /// at once. The store file stays, holding no rows.
    func deleteAll() throws {
        let context = container.mainContext
        for poem in try context.fetch(FetchDescriptor<Poem>()) { context.delete(poem) }
        for session in try context.fetch(FetchDescriptor<CaptureSession>()) { context.delete(session) }
        for moment in try context.fetch(FetchDescriptor<MomentRecord>()) { context.delete(moment) }
        try context.save()
    }

    /// The store and its SQLite side files.
    nonisolated static func files(in directory: URL) -> [URL] {
        ["Library.store", "Library.store-wal", "Library.store-shm"].map { directory.appending(path: $0) }
    }

    /// nil for a session still being written or whose manifest is unreadable (recovery rebuilds it).
    private nonisolated static func snapshot(_ summary: SpoolSessionSummary) -> SessionSnapshot? {
        guard summary.isDone, let manifest = summary.manifest else { return nil }
        let record = try? CaptureRecord.read(from: summary.session.captureRecordURL)
        return SessionSnapshot(
            spoolSessionID: summary.id, startedAt: record?.startedAt ?? manifest.createdAt,
            stoppedAt: record?.stoppedAt ?? manifest.finishedAt, durationSec: manifest.durationSec,
            stopReason: record?.stopReason, hasAudio: summary.hasAudio)
    }

    private nonisolated static func readTranscript(_ summary: SpoolSessionSummary) -> (SessionTranscript, Bool)? {
        (try? SessionTranscript.read(from: summary.session.transcriptURL)).map { ($0, summary.hasAudio) }
    }
}
