import Testing
@testable import AnamnesisKit

@Suite("LineBreaker")
struct LineBreakerTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let words: [TranscriptWord]
        let expected: String
        var testDescription: String { name }
    }

    static func w(_ text: String, _ start: Double, _ end: Double) -> TranscriptWord {
        TranscriptWord(text: text, startSec: start, endSec: end)
    }

    static let cases: [Case] = [
        Case(name: "no words", words: [], expected: ""),
        Case(name: "single word", words: [w("alone", 0, 1)], expected: "alone"),
        Case(name: "zero gap is a space", words: [w("a", 0, 1), w("b", 1, 2)], expected: "a b"),
        Case(name: "gap below lineGap is a space", words: [w("a", 0, 1), w("b", 1.59, 2)], expected: "a b"),
        Case(name: "gap at lineGap is a newline", words: [w("a", 0, 1), w("b", 1.6, 2)], expected: "a\nb"),
        Case(name: "gap at stanzaGap is a blank line", words: [w("a", 0, 1), w("b", 2.5, 3)], expected: "a\n\nb"),
        Case(name: "huge gap is still one blank line", words: [w("a", 0, 1), w("b", 900, 901)], expected: "a\n\nb"),
        Case(name: "overlapping timings never break", words: [w("a", 0, 2), w("b", 1, 1.5), w("c", 2.1, 3)],
             expected: "a b c"),
        Case(name: "unsorted words are ordered", words: [w("b", 2, 3), w("a", 0, 1)], expected: "a\nb"),
        Case(name: "mixed poem layout",
             words: [w("Do", 0, 0.2), w("not", 0.3, 0.5), w("go", 0.6, 0.8), w("gentle", 1.6, 2.0),
                     w("Rage", 4.0, 4.3), w("rage", 4.4, 4.7)],
             expected: "Do not go\ngentle\n\nRage rage")
    ]

    @Test("infers line and stanza breaks from pauses", arguments: cases)
    func layout(_ testCase: Case) {
        let config = LineBreakConfig(lineGap: 0.6, stanzaGap: 1.5)
        #expect(LineBreaker.format(testCase.words, config: config) == testCase.expected)
    }

    static func segment(_ words: [TranscriptWord]) -> TranscriptSegment {
        TranscriptSegment(text: words.map(\.text).joined(separator: " "), startSec: words.first?.startSec ?? 0,
                          endSec: words.last?.endSec ?? 0, words: words)
    }

    @Test("every result boundary is a line break, even with no pause (D-024)")
    func resultBoundaries() {
        let segments = [Self.segment([Self.w("Do", 0, 0.3), Self.w("not", 0.3, 0.6), Self.w("go", 0.6, 1.0)]),
                        Self.segment([Self.w("gentle", 1.0, 1.4), Self.w("into", 1.4, 1.7)])]
        #expect(LineBreaker.format(segments) == "Do not go\ngentle into")
    }

    @Test("results at least stanzaGap apart start a stanza")
    func stanzaBetweenResults() {
        let segments = [Self.segment([Self.w("one", 0, 1)]), Self.segment([Self.w("two", 2.5, 3)]),
                        Self.segment([Self.w("three", 3.2, 4)])]
        #expect(LineBreaker.format(segments) == "one\n\ntwo\nthree")
    }

    @Test("pauses inside a result still break lines")
    func pauseInsideResult() {
        let segments = [Self.segment([Self.w("a", 0, 1), Self.w("b", 1.7, 2), Self.w("c", 2, 2.5)])]
        #expect(LineBreaker.format(segments) == "a\nb c")
    }

    @Test("results are ordered by start; no results is empty text")
    func orderingAndEmpty() {
        let segments = [Self.segment([Self.w("later", 5, 6)]), Self.segment([Self.w("first", 0, 1)])]
        #expect(LineBreaker.format(segments) == "first\n\nlater")
        #expect(LineBreaker.format([TranscriptSegment]()).isEmpty)
    }

    @Test("results without words are whole lines")
    func untimedSegments() {
        let segments = [TranscriptSegment(text: "first line", startSec: 0, endSec: 2),
                        TranscriptSegment(text: "second line", startSec: 2.1, endSec: 4)]
        #expect(LineBreaker.format(segments) == "first line\nsecond line")
    }
}
