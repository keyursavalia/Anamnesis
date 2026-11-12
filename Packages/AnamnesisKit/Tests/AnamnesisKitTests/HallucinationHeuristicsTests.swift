import Testing
@testable import AnamnesisKit

@Suite("HallucinationHeuristics")
struct HallucinationHeuristicsTests {
    static let config = HallucinationConfig()

    @Test("detects n-gram loops", arguments: [
        ("thank you thank you thank you", true),
        ("you you you you you you", true),
        ("and the night and the night and the night", true),
        ("never, never, never, never, never", false), // a refrain shorter than minLoopTokens
        ("rage, rage against the dying of the light", false),
        ("", false)
    ])
    func loops(_ text: String, _ expected: Bool) {
        let tokens = HallucinationHeuristics.tokens(of: text)
        #expect(HallucinationHeuristics.hasRepeatedNGramLoop(tokens, config: Self.config) == expected)
    }

    @Test("tokens ignore case and punctuation, keep apostrophes")
    func tokens() {
        #expect(HallucinationHeuristics.tokens(of: "Don't, GO!  gentle.") == ["don't", "go", "gentle"])
    }

    @Test("flags low confidence only when reported")
    func lowConfidence() {
        let low = TranscriptSegment(text: "a", startSec: 0, endSec: 1, confidence: 0.1)
        let none = TranscriptSegment(text: "a", startSec: 0, endSec: 1)
        #expect(HallucinationHeuristics.flags(for: low, speechRegions: nil) == [.lowConfidence])
        #expect(HallucinationHeuristics.flags(for: none, speechRegions: nil).isEmpty)
    }

    @Test("speech coverage merges overlapping regions and ignores non-speech")
    func coverage() {
        let segment = TranscriptSegment(text: "a", startSec: 0, endSec: 10)
        let regions = [SpeechRegion(startSec: 0, endSec: 3, speechDetected: true),
                       SpeechRegion(startSec: 2, endSec: 4, speechDetected: true),
                       SpeechRegion(startSec: 4, endSec: 10, speechDetected: false)]
        #expect(abs(HallucinationHeuristics.speechCoverage(of: segment, in: regions) - 0.4) < 1e-9)
    }

    @Test("flags text during no-speech, skips the check without a detector")
    func noSpeech() {
        let segment = TranscriptSegment(text: "ghost words", startSec: 5, endSec: 8, confidence: 0.9)
        let silent = [SpeechRegion(startSec: 0, endSec: 10, speechDetected: false)]
        #expect(HallucinationHeuristics.flags(for: segment, speechRegions: silent) == [.noSpeechOverlap])
        #expect(HallucinationHeuristics.flags(for: segment, speechRegions: []).isEmpty)
        #expect(HallucinationHeuristics.flags(for: segment, speechRegions: nil).isEmpty)
        let spoken = [SpeechRegion(startSec: 4, endSec: 9, speechDetected: true)]
        #expect(HallucinationHeuristics.flags(for: segment, speechRegions: spoken).isEmpty)
    }

    @Test("a zero-length segment is covered if a speech region contains it")
    func zeroLength() {
        let segment = TranscriptSegment(text: "a", startSec: 2, endSec: 2)
        #expect(HallucinationHeuristics.speechCoverage(
            of: segment, in: [SpeechRegion(startSec: 1, endSec: 3, speechDetected: true)]) == 1)
        #expect(HallucinationHeuristics.speechCoverage(of: segment, in: []) == 0)
    }
}
