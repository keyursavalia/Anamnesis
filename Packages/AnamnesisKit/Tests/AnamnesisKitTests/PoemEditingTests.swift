import Foundation
import SwiftData
import Testing
@testable import AnamnesisKit

@Suite("Poem editing")
struct PoemEditingTests {
    let start = Date(timeIntervalSince1970: 1_794_000_000)

    static func word(_ text: String, _ confidence: Double = 0.9) -> TranscriptWord {
        TranscriptWord(text: text, startSec: 0, endSec: 0, confidence: confidence)
    }

    static func substrings(_ body: String, _ ranges: [Range<Int>]) -> [String] {
        let chars = Array(body)
        return ranges.map { String(chars[$0]) }
    }

    // MARK: - Unsure words

    @Test("unsure words are found in a fresh body, across lines and stanzas")
    func unsureFresh() {
        let words = [Self.word("I"), Self.word("wandered,", 0.3), Self.word("lonely"), Self.word("as"),
                     Self.word("a", 0.2), Self.word("cloud", 0.4)]
        let body = "I wandered,\nlonely as\n\na cloud"
        #expect(Self.substrings(body, UnsureWords.ranges(in: body, words: words)) == ["wandered,", "a", "cloud"])
    }

    @Test("an edited word loses its highlight and the rest keep theirs")
    func unsureEdited() {
        let words = [Self.word("the"), Self.word("nite", 0.3), Self.word("is"), Self.word("dark", 0.4)]
        let body = "the night is dark"
        #expect(Self.substrings(body, UnsureWords.ranges(in: body, words: words)) == ["dark"])
    }

    @Test("repeated words match in order and inside words never match")
    func unsureRepeated() {
        let words = [Self.word("a"), Self.word("cat"), Self.word("a", 0.1)]
        let body = "a cat a"
        #expect(UnsureWords.ranges(in: body, words: words) == [6..<7])
        let inside = [Self.word("at", 0.1)]
        #expect(UnsureWords.ranges(in: "cat", words: inside).isEmpty)
    }

    @Test("the walk finds its place again after an inserted line")
    func unsureAfterInsert() {
        let words = [Self.word("one"), Self.word("two"), Self.word("three"), Self.word("four", 0.2)]
        let inserted = String(repeating: "x ", count: 30)
        let body = "one \(inserted)two three four"
        #expect(Self.substrings(body, UnsureWords.ranges(in: body, words: words)) == ["four"])
    }

    @Test("words follow LineBreaker's order")
    func unsureWordOrder() {
        let late = TranscriptSegment(text: "b", startSec: 5, endSec: 6)
        let early = TranscriptSegment(text: "a", startSec: 0, endSec: 1)
        #expect(UnsureWords.words(of: [late, early]).map(\.text) == ["a", "b"])
    }

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

    // MARK: - Tags

    @Test("tags are trimmed and deduplicated regardless of case")
    func tags() {
        #expect(PoemTags.parse(" love, Rilke ,, love,LOVE, night ") == ["love", "Rilke", "night"])
        #expect(PoemTags.format(["a", "b"]) == "a, b")
        #expect(PoemTags.parse("").isEmpty)
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
        draft.tagsText = "love, Love, night"
        draft.apply(to: poem, now: start.addingTimeInterval(5))
        #expect(!poem.userEdited)
        #expect(poem.title == nil)
        #expect(poem.poet == "Rumi")
        #expect(poem.tags == ["love", "night"])

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
                                                     sourceNote: "Instagram reel", tagsText: "love, night"))
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
        poem.tags = ["x"]

        let other = try #require(poem.splitOff(at: 8, in: context, now: start))
        try context.save()
        #expect(poem.body == "poem one")
        #expect(other.body == "poem two")
        #expect(poem.body + "\n\n" + other.body == "poem one\n\npoem two")
        #expect(moment.poem?.id == poem.id)
        #expect(other.moment == nil)
        #expect(other.sourceSessionID == "s1")
        #expect(other.poet == "Anon")
        #expect(other.tags == ["x"])
        #expect(other.title == nil)
        #expect(try context.fetchCount(FetchDescriptor<Poem>()) == 2)
        #expect(poem.splitOff(at: 0, in: context) == nil)
    }
}
