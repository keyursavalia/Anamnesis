import Foundation
import SwiftData
import Testing
@testable import AnamnesisKit

@Suite("Library store and importer")
struct LibraryImporterTests {
    let start = Date(timeIntervalSince1970: 1_794_000_000)

    func makeImporter() throws -> (LibraryImporter, ModelContainer) {
        let container = try ModelContainer.library(at: nil)
        return (LibraryImporter(modelContainer: container), container)
    }

    static func seg(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(text: text, startSec: start, endSec: end, confidence: 0.8)
    }

    func transcript(_ id: String = "s1",
                    segments: [TranscriptSegment] = [seg("one", 0, 2), seg("two", 2.5, 4), seg("three", 30, 32)],
                    version: Int = SessionTranscript.currentVersion) -> SessionTranscript {
        let inner = Transcript(source: "session \(id)", locale: "en_US", config: TranscriptionConfig(),
                               createdAt: start, segments: segments, speechRegions: nil, metrics: nil)
        var record = CaptureRecord(sessionID: id, startedAt: start, start: PowerSnapshot(
            takenAt: start, batteryLevel: 0.9, batteryState: .unplugged, thermalState: "nominal", lowPowerMode: false))
        record.markStopped(at: start.addingTimeInterval(60), reason: "user", power: record.start)
        var value = SessionTranscript(sessionID: id, transcript: inner, metrics: SessionMetrics(
            capture: record, transcriptionStartedAt: start.addingTimeInterval(61),
            readyAt: start.addingTimeInterval(62), audioSec: 60))
        value.version = version
        return value
    }

    func sessions(_ container: ModelContainer) throws -> [CaptureSession] {
        try ModelContext(container).fetch(FetchDescriptor<CaptureSession>())
    }

    func moments(_ container: ModelContainer) throws -> [MomentRecord] {
        try ModelContext(container).fetch(FetchDescriptor<MomentRecord>(sortBy: [SortDescriptor(\.index)]))
    }

    // MARK: - Drafts

    @Test("drafts follow the transcript's Moments with D-024 layout, confidence and flags")
    func drafts() throws {
        let value = transcript(segments: [Self.seg("one", 0, 2), Self.seg("one one one one one one one one", 2.1, 4),
                                           Self.seg("two", 30, 31)])
        let drafts = try MomentDraft.drafts(from: value)
        #expect(drafts.map(\.index) == [0, 1])
        #expect(drafts[0].poemText == "one\none one one one one one one one")
        #expect(drafts[0].meanConfidence == 0.8)
        #expect(drafts[0].flags == [.repeatedNGramLoop])
        #expect(drafts[1].flags.isEmpty)
        let segments = try SessionFileCodec.decoder.decode([TranscriptSegment].self, from: drafts[0].segmentsData)
        #expect(segments.map(\.text) == ["one", "one one one one one one one one"])
    }

    // MARK: - Import

    @Test("importing a transcript stores the session and its Moments")
    func importStores() async throws {
        let (importer, container) = try makeImporter()
        let outcome = try await importer.importTranscript(transcript(), audioDeleted: true)
        #expect(outcome == .imported(moments: 2))
        let session = try #require(try sessions(container).first)
        #expect(session.state == .transcribed)
        #expect(session.audioDeleted)
        #expect(session.stopReason == "user")
        #expect(session.metrics?.latencySec == 2)
        #expect(session.sortedMoments.map(\.text) == ["one two", "three"])
    }

    @Test("every imported Moment is kept as a poem at once, dated when it was heard (spec 016 R1)")
    func importKeeps() async throws {
        let (importer, container) = try makeImporter()
        _ = try await importer.importTranscript(transcript(), audioDeleted: true)
        let session = try #require(try sessions(container).first)
        #expect(session.sortedMoments.allSatisfy { $0.review == .saved && $0.poem != nil })
        let poems = try ModelContext(container).fetch(FetchDescriptor<Poem>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(poems.map(\.body) == session.sortedMoments.map(\.poemText))
        #expect(poems.allSatisfy { $0.sourceSessionID == session.spoolSessionID })
        let heardAt = session.sortedMoments.map { session.startedAt.addingTimeInterval($0.startSec) }
        #expect(poems.map(\.createdAt) == heardAt)
    }

    @Test("Moments left waiting before spec 016 are kept; dismissed ones are not")
    func keepPending() async throws {
        let (importer, container) = try makeImporter()
        let context = ModelContext(container)
        let session = CaptureSession(spoolSessionID: "old", startedAt: start, durationSec: 60)
        context.insert(session)
        for draft in try MomentDraft.drafts(from: transcript("old")) {
            let moment = MomentRecord(draft)
            context.insert(moment)
            moment.session = session
        }
        session.sortedMoments[1].review = .dismissed
        try context.save()
        #expect(try await importer.keepPendingMoments() == 1)
        #expect(try await importer.keepPendingMoments() == 0)
        let stored = try moments(container).sorted { $0.index < $1.index }
        #expect(stored.map(\.review) == [.saved, .dismissed])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Poem>()) == 1)
    }

    @Test("importing the same transcript twice changes nothing")
    func idempotent() async throws {
        let (importer, container) = try makeImporter()
        _ = try await importer.importTranscript(transcript(), audioDeleted: false)
        let again = try await importer.importTranscript(transcript(), audioDeleted: false)
        #expect(again == .alreadyImported)
        #expect(try sessions(container).count == 1)
        #expect(try moments(container).count == 2)
    }

    @Test("a re-import with another version replaces Moments that have no poems yet (F-043)")
    func replaces() async throws {
        let (importer, container) = try makeImporter()
        // Moments stored without the importer (as before spec 016) have no poems.
        let context = ModelContext(container)
        let session = CaptureSession(spoolSessionID: "s1", startedAt: start, durationSec: 60)
        context.insert(session)
        for draft in try MomentDraft.drafts(from: transcript()) {
            let moment = MomentRecord(draft)
            context.insert(moment)
            moment.session = session
        }
        try context.save()
        let rerun = transcript(segments: [Self.seg("only", 0, 1)], version: 0)
        #expect(try await importer.importTranscript(rerun, audioDeleted: false) == .imported(moments: 1))
        #expect(try moments(container).map(\.text) == ["only"])
    }

    @Test("a re-import never replaces Moments that are already poems")
    func keepsPoems() async throws {
        let (importer, container) = try makeImporter()
        _ = try await importer.importTranscript(transcript(), audioDeleted: false)
        let rerun = transcript(segments: [Self.seg("only", 0, 1)], version: 0)
        #expect(try await importer.importTranscript(rerun, audioDeleted: false) == .keptReviewedMoments)
        #expect(try moments(container).count == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Poem>()) == 2)
    }

    // MARK: - Sync, failures, deletion

    @Test("sync inserts new sessions once and never deletes missing ones")
    func sync() async throws {
        let (importer, container) = try makeImporter()
        let snapshot = SessionSnapshot(spoolSessionID: "a", startedAt: start, durationSec: 10, hasAudio: true)
        #expect(try await importer.sync([snapshot]) == 1)
        #expect(try await importer.sync([snapshot]) == 0)
        _ = try await importer.importTranscript(transcript("b"), audioDeleted: true)
        #expect(try await importer.sync([]) == 0)
        #expect(Set(try sessions(container).map(\.spoolSessionID)) == ["a", "b"])
        #expect(try await importer.importedSessionIDs() == ["b"])
        #expect(try await importer.transcribableSessionIDs(maxAttempts: 3) == ["a"])
    }

    @Test("failures count attempts and stop automatic retries at the limit; Retry clears the failure")
    func failures() async throws {
        let (importer, container) = try makeImporter()
        try await importer.sync([SessionSnapshot(spoolSessionID: "a", startedAt: start, durationSec: 10,
                                                 hasAudio: true)])
        for _ in 0..<3 { try await importer.recordFailure(sessionID: "a", text: "model missing") }
        #expect(try await importer.transcribableSessionIDs(maxAttempts: 3).isEmpty)
        let session = try #require(try sessions(container).first)
        #expect(session.state == .failed)
        #expect(session.attempts == 3)
        try await importer.clearFailure(sessionID: "a")
        #expect(try await importer.transcribableSessionIDs(maxAttempts: 3) == ["a"])
    }

    @Test("deleting a session removes its Moments and keeps poems saved from them")
    func delete() async throws {
        let (importer, container) = try makeImporter()
        // Import keeps both Moments as poems (spec 016 R1).
        _ = try await importer.importTranscript(transcript(), audioDeleted: true)

        try await importer.delete(sessionID: "s1")
        #expect(try sessions(container).isEmpty)
        #expect(try moments(container).isEmpty)
        let poems = try ModelContext(container).fetch(FetchDescriptor<Poem>())
        #expect(poems.count == 2)
        #expect(poems.allSatisfy { $0.moment == nil && $0.sourceSessionID == "s1" })
    }
}
