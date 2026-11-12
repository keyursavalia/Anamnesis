import Testing
@testable import AnamnesisKit

@Suite("LineBreakScore")
struct LineBreakScoreTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let reference: String
        let hypothesis: String
        /// (truth breaks, predicted breaks, matched).
        let counts: [Int]
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "identical layout", reference: "a b c\nd e f\ng h", hypothesis: "a b c\nd e f\ng h",
             counts: [2, 2, 2]),
        Case(name: "no predicted breaks", reference: "a b\nc d", hypothesis: "a b c d", counts: [1, 0, 0]),
        Case(name: "off by one word matches", reference: "a b c\nd e f", hypothesis: "a b c d\ne f",
             counts: [1, 1, 1]),
        Case(name: "off by two words does not", reference: "a b c\nd e f", hypothesis: "a\nb c d e f",
             counts: [1, 1, 0]),
        Case(name: "truth without breaks", reference: "a b c d", hypothesis: "a b\nc d", counts: [0, 1, 0]),
        Case(name: "stanza blank line is one break", reference: "a b\n\nc d", hypothesis: "a b\nc d",
             counts: [1, 1, 1]),
        Case(name: "substituted word before the break", reference: "the night\nis long",
             hypothesis: "the knight\nis long", counts: [1, 1, 1]),
        Case(name: "inserted words do not shift positions", reference: "a b c\nd e f",
             hypothesis: "x y a b c\nd e f", counts: [1, 1, 1]),
        Case(name: "deleted words do not shift positions", reference: "a b c\nd e f\ng h i",
             hypothesis: "a c\nd e f\ng h i", counts: [2, 2, 2]),
        Case(name: "two predictions near one truth match once", reference: "a b c\nd e f",
             hypothesis: "a b\nc\nd e f", counts: [1, 2, 1]),
        Case(name: "trailing and leading newlines ignored", reference: "\na b\nc d\n", hypothesis: "a b\nc d\n\n",
             counts: [1, 1, 1]),
        Case(name: "punctuation-only line ignored", reference: "a b\n—\nc d", hypothesis: "a b\nc d",
             counts: [1, 1, 1])
    ]

    @Test("scores break positions with ±1 word tolerance", arguments: cases)
    func scores(_ testCase: Case) {
        let score = LineBreakScorer.score(reference: testCase.reference, hypothesis: testCase.hypothesis)
        #expect([score.truthBreaks, score.predictedBreaks, score.matched] == testCase.counts)
    }

    @Test("precision, recall and F1, with nil when undefined")
    func rates() throws {
        let score = LineBreakScore(truthBreaks: 4, predictedBreaks: 2, matched: 2)
        #expect(score.precision == 1)
        #expect(score.recall == 0.5)
        #expect(abs(try #require(score.f1) - 2.0 / 3) < 1e-9)
        #expect(LineBreakScore(truthBreaks: 3, predictedBreaks: 0, matched: 0).precision == nil)
        #expect(LineBreakScore(truthBreaks: 0, predictedBreaks: 2, matched: 0).recall == nil)
        #expect(LineBreakScore(truthBreaks: 2, predictedBreaks: 2, matched: 0).f1 == 0)
    }

    @Test("greedy matching is one-to-one on positions")
    func positions() {
        #expect(LineBreakScorer.score(truthBreaks: [5, 6], predictedBreaks: [5]).matched == 1)
        #expect(LineBreakScorer.score(truthBreaks: [4, 6], predictedBreaks: [5, 5]).matched == 2)
        #expect(LineBreakScorer.score(truthBreaks: [2], predictedBreaks: [4], tolerance: 2).matched == 1)
    }
}
