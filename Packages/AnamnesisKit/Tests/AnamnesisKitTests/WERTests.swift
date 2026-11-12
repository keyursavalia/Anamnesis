import Testing
@testable import AnamnesisKit

@Suite("WER")
struct WERTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let reference: String
        let hypothesis: String
        /// (S, D, I), hand-computed.
        let counts: [Int]
        let wer: Double?
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "identical", reference: "the cat sat", hypothesis: "the cat sat", counts: [0, 0, 0], wer: 0),
        Case(name: "deletion", reference: "the cat sat", hypothesis: "the cat", counts: [0, 1, 0], wer: 1.0 / 3),
        Case(name: "insertion", reference: "the cat sat", hypothesis: "the cat sat down", counts: [0, 0, 1],
             wer: 1.0 / 3),
        Case(name: "substitution", reference: "the cat sat", hypothesis: "the bat sat", counts: [1, 0, 0],
             wer: 1.0 / 3),
        Case(name: "both empty", reference: "", hypothesis: "", counts: [0, 0, 0], wer: 0),
        Case(name: "empty reference is undefined", reference: "", hypothesis: "ghost", counts: [0, 0, 1], wer: nil),
        Case(name: "empty hypothesis", reference: "a b", hypothesis: "", counts: [0, 2, 0], wer: 1),
        Case(name: "repeated word dropped", reference: "rage rage against", hypothesis: "rage against",
             counts: [0, 1, 0], wer: 1.0 / 3),
        Case(name: "shift is one deletion + one insertion, not four substitutions", reference: "a b c d",
             hypothesis: "b c d e", counts: [0, 1, 1], wer: 0.5),
        Case(name: "case and punctuation ignored", reference: "Do not go, gentle!", hypothesis: "do not go gentle",
             counts: [0, 0, 0], wer: 0),
        Case(name: "curly apostrophe equals straight", reference: "don\u{2019}t", hypothesis: "don't",
             counts: [0, 0, 0], wer: 0),
        Case(name: "combining mark equals precomposed", reference: "café", hypothesis: "cafe\u{0301}",
             counts: [0, 0, 0], wer: 0),
        Case(name: "missing diacritic is an error", reference: "café", hypothesis: "cafe", counts: [1, 0, 0], wer: 1),
        Case(name: "hyphen splits words", reference: "well-known", hypothesis: "well known", counts: [0, 0, 0], wer: 0),
        Case(name: "numbers are not spelled out", reference: "three roses", hypothesis: "3 roses",
             counts: [1, 0, 0], wer: 0.5),
        Case(name: "WER can exceed 1", reference: "a", hypothesis: "b c d", counts: [1, 0, 2], wer: 3)
    ]

    @Test("hand-computed S/D/I and WER", arguments: cases)
    func handComputed(_ testCase: Case) throws {
        let result = WER.score(reference: testCase.reference, hypothesis: testCase.hypothesis)
        #expect([result.substitutions, result.deletions, result.insertions] == testCase.counts)
        if let expected = testCase.wer {
            let wer = try #require(result.wer)
            #expect(abs(wer - expected) < 1e-9)
        } else {
            #expect(result.wer == nil)
        }
    }

    @Test("alignment lists every word with its operation and hypothesis index")
    func alignment() {
        let result = WER.score(reference: "a b c", hypothesis: "a x c d")
        #expect(result.alignment == [
            AlignedWord(operation: .match, reference: "a", hypothesis: "a", hypothesisIndex: 0),
            AlignedWord(operation: .substitution, reference: "b", hypothesis: "x", hypothesisIndex: 1),
            AlignedWord(operation: .match, reference: "c", hypothesis: "c", hypothesisIndex: 2),
            AlignedWord(operation: .insertion, reference: nil, hypothesis: "d", hypothesisIndex: 3)
        ])
        #expect(result.referenceWords == 3)
        #expect(result.errors == 2)
    }

    @Test("CER counts characters including spaces")
    func cer() throws {
        #expect(try #require(WER.cer(reference: "abc", hypothesis: "abd")) == 1.0 / 3)
        #expect(WER.cer(reference: "Go, gentle", hypothesis: "go gentle") == 0)
        #expect(WER.cer(reference: "", hypothesis: "x") == nil)
    }
}
