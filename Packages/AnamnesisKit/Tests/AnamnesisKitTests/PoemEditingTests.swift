import Foundation
import SwiftData
import Testing
@testable import AnamnesisKit

@Suite("Poem editing")
struct PoemEditingTests {
    let start = Date(timeIntervalSince1970: 1_794_000_000)

    // MARK: - Split

    @Test("the halves join back with the whitespace removed at the cut")
    func splitJoins() throws {
        let body = "first poem line\nsecond line\n\nnext poem\nends"
        let offset = Array(body).count - "next poem\nends".count - 1
        let (first, second) = try #require(PoemSplit.split(body, at: offset))
        #expect(first == "first poem line\nsecond line")
        #expect(second == "next poem\nends")
        #expect(first + "\n\n" + second == body)
    }

    @Test("a cut at either end or in blank text gives nothing")
    func splitEmpty() {
        #expect(PoemSplit.split("abc", at: 0) == nil)
        #expect(PoemSplit.split("abc", at: 3) == nil)
        #expect(PoemSplit.split("abc\n\n", at: 4) == nil)
        #expect(PoemSplit.split("abc", at: 9) == nil)
        #expect(PoemSplit.split("a b", at: 1).map { [$0.first, $0.second] } == ["a", "b"])
    }

    // MARK: - History

    @Test("quick changes merge into one undo step; undo and redo walk the steps")
    func history() {
        var history = EditHistory("a")
        history.record("ab", at: start)
        history.record("abc", at: start.addingTimeInterval(0.5))
        history.record("abcd", at: start.addingTimeInterval(3))
        #expect(history.undo() == "abc")
        #expect(history.undo() == "a")
        #expect(history.undo() == nil)
        #expect(history.redo() == "abc")
        history.record("x", at: start.addingTimeInterval(10))
        #expect(!history.canRedo)
        #expect(history.current == "x")
    }

    @Test("history keeps at most `limit` steps and ignores no-op changes")
    func historyLimit() {
        var history = EditHistory(0, coalesce: 0, limit: 3)
        for value in 1...5 { history.record(value, at: start.addingTimeInterval(Double(value))) }
        history.record(5, at: start.addingTimeInterval(9))
        var undone: [Int] = []
        while let value = history.undo() { undone.append(value) }
        #expect(undone == [4, 3, 2])
    }

    // MARK: - Draft and store

    @Test("a draft writes every field, empties become nil, userEdited only on a body change; it persists (AC1)")
    func draftApply() throws {
        let container = try ModelContainer.library(at: nil)
        let context = ModelContext(container)
        let poem = Poem(body: "line one\nline two", createdAt: start)
        context.insert(poem)

        var draft = PoemDraft(poem: poem)
        draft.title = "  "
        draft.poet = " Rumi "
        draft.apply(to: poem, now: start.addingTimeInterval(5))
        #expect(!poem.userEdited)
        #expect(poem.title == nil)
        #expect(poem.poet == "Rumi")

        draft.body = "line one\nline 2"
        draft.sourceNote = "Instagram reel"
        draft.apply(to: poem, now: start.addingTimeInterval(9))
        try context.save()

        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<Poem>()).first)
        #expect(stored.body == "line one\nline 2")
        #expect(stored.userEdited)
        #expect(stored.sourceNote == "Instagram reel")
        #expect(stored.updatedAt == start.addingTimeInterval(9))
        #expect(PoemDraft(poem: stored) == PoemDraft(body: "line one\nline 2", poet: "Rumi",
                                                     sourceNote: "Instagram reel"))
    }

    @Test("splitting off keeps the Moment on the first poem and carries the details to the second (AC2)")
    func splitOff() throws {
        let context = ModelContext(try ModelContainer.library(at: nil))
        let session = CaptureSession(spoolSessionID: "s1", startedAt: start, durationSec: 60)
        context.insert(session)
        let draft = MomentDraft(index: 0, startSec: 0, endSec: 10, text: "a b", poemText: "poem one\n\npoem two",
                                meanConfidence: 0.9, flags: [], segmentsData: Data("[]".utf8))
        let moment = MomentRecord(draft)
        context.insert(moment)
        moment.session = session
        let poem = moment.saveAsPoem(in: context)
        poem.poet = "Anon"

        let other = try #require(poem.splitOff(at: 8, in: context, now: start))
        try context.save()
        #expect(poem.body == "poem one")
        #expect(other.body == "poem two")
        #expect(poem.body + "\n\n" + other.body == "poem one\n\npoem two")
        #expect(moment.poem?.id == poem.id)
        #expect(other.moment == nil)
        #expect(other.sourceSessionID == "s1")
        #expect(other.poet == "Anon")
        #expect(other.title == nil)
        #expect(try context.fetchCount(FetchDescriptor<Poem>()) == 2)
        #expect(poem.splitOff(at: 0, in: context) == nil)
    }
}
