import Foundation
import SwiftData
import Testing
@testable import AnamnesisKit

@Suite("Keeping Moments as poems")
struct MomentReviewTests {
    let start = Date(timeIntervalSince1970: 1_794_000_000)

    /// One session "s1" with Moments "one\ntwo" and "three", in a fresh in-memory store.
    func makeSession() throws -> (ModelContext, CaptureSession) {
        let context = ModelContext(try ModelContainer.library(at: nil))
        let session = CaptureSession(spoolSessionID: "s1", startedAt: start, durationSec: 60)
        context.insert(session)
        let transcript = LibraryImporterTests().transcript(segments: [
            LibraryImporterTests.seg("one", 0, 2), LibraryImporterTests.seg("two", 2.5, 4),
            LibraryImporterTests.seg("three", 30, 32)
        ])
        for draft in try MomentDraft.drafts(from: transcript) {
            let moment = MomentRecord(draft)
            context.insert(moment)
            moment.session = session
        }
        try context.save()
        return (context, session)
    }

    func poemCount(_ context: ModelContext) throws -> Int { try context.fetchCount(FetchDescriptor<Poem>()) }

    @Test("Save as poem keeps the line breaks, links the poem and marks the Moment saved")
    func save() throws {
        let (context, session) = try makeSession()
        let moment = session.sortedMoments[0]
        let poem = moment.saveAsPoem(in: context, now: start)
        try context.save()
        #expect(poem.body == "one\ntwo")
        #expect(poem.sourceSessionID == "s1")
        #expect(poem.createdAt == start)
        #expect(moment.poem?.id == poem.id)
        #expect(moment.review == .saved)
        #expect(try poemCount(context) == 1)
    }

    @Test("saving twice returns the same poem")
    func saveTwice() throws {
        let (context, session) = try makeSession()
        let moment = session.sortedMoments[0]
        let first = moment.saveAsPoem(in: context)
        let second = moment.saveAsPoem(in: context)
        try context.save()
        #expect(first.id == second.id)
        #expect(try poemCount(context) == 1)
    }

    @Test("a Moment dismissed before spec 016 can still be kept")
    func saveDismissed() throws {
        let (context, session) = try makeSession()
        let moment = session.sortedMoments[1]
        moment.review = .dismissed
        let poem = moment.saveAsPoem(in: context)
        #expect(moment.review == .saved)
        #expect(poem.body == "three")
    }

    @Test("the session counts the poems it still has in the library")
    func keptCount() throws {
        let (context, session) = try makeSession()
        #expect(session.keptPoemCount == 0)
        let poems = session.sortedMoments.map { $0.saveAsPoem(in: context) }
        #expect(session.keptPoemCount == 2)
        context.delete(poems[0])
        try context.save()
        #expect(session.keptPoemCount == 1)
    }
}
