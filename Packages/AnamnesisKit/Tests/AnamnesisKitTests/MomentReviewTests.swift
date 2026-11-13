import Foundation
import SwiftData
import Testing
@testable import AnamnesisKit

@Suite("Moments review")
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

    @Test("dismiss and restore round-trip; a saved Moment cannot be dismissed")
    func dismissRestore() throws {
        let (context, session) = try makeSession()
        let moments = session.sortedMoments
        moments[0].dismiss()
        #expect(moments[0].review == .dismissed)
        moments[0].restore()
        #expect(moments[0].review == .new)
        moments[1].saveAsPoem(in: context)
        moments[1].dismiss()
        moments[1].restore()
        #expect(moments[1].review == .saved)
    }

    @Test("a dismissed Moment can still be saved")
    func saveDismissed() throws {
        let (context, session) = try makeSession()
        let moment = session.sortedMoments[1]
        moment.dismiss()
        let poem = moment.saveAsPoem(in: context)
        #expect(moment.review == .saved)
        #expect(poem.body == "three")
    }

    @Test("the session counts new and reviewed Moments, and the counts survive a fresh context")
    func counts() throws {
        let (context, session) = try makeSession()
        #expect(session.newMomentCount == 2)
        session.sortedMoments[0].dismiss()
        try context.save()
        #expect(session.newMomentCount == 1)
        #expect(session.reviewedMomentCount == 1)
        let fresh = ModelContext(context.container)
        let new = MomentReview.new.rawValue
        #expect(try fresh.fetchCount(FetchDescriptor<MomentRecord>(predicate: #Predicate { $0.reviewRaw == new })) == 1)
    }
}
