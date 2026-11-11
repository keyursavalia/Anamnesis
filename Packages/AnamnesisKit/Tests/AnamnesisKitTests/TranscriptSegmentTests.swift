import Foundation
import Testing
@testable import AnamnesisKit

@Suite("TranscriptSegment")
struct TranscriptSegmentTests {
    @Test("flattens timed runs into words, skipping whitespace runs")
    func flattensRuns() throws {
        let runs = [
            TranscriptRun(text: "Do", startSec: 1.0, endSec: 1.2, confidence: 0.9),
            TranscriptRun(text: " "),
            TranscriptRun(text: "not ", startSec: 1.3, endSec: 1.5, confidence: 0.7),
            TranscriptRun(text: "go", startSec: 1.6, endSec: 2.0, confidence: 0.8)
        ]
        let segment = try #require(TranscriptSegment(runs: runs, resultStartSec: 0.5, resultEndSec: 2.5))
        #expect(segment.text == "Do not go")
        #expect(segment.words?.map(\.text) == ["Do", "not", "go"])
        #expect(segment.startSec == 1.0)
        #expect(segment.endSec == 2.0)
        #expect(abs((segment.confidence ?? 0) - 0.8) < 1e-9)
    }

    @Test("falls back to the result range when no run is timed")
    func untimedRuns() throws {
        let segment = try #require(TranscriptSegment(runs: [TranscriptRun(text: "hello world")],
                                                     resultStartSec: 3, resultEndSec: 4))
        #expect(segment.words == nil)
        #expect(segment.confidence == nil)
        #expect(segment.startSec == 3)
        #expect(segment.endSec == 4)
        #expect(segment.timedTokens == [TranscriptWord(text: "hello world", startSec: 3, endSec: 4)])
    }

    @Test("a whitespace-only result yields no segment")
    func whitespaceOnly() {
        #expect(TranscriptSegment(runs: [TranscriptRun(text: "  ")], resultStartSec: 0, resultEndSec: 1) == nil)
        #expect(TranscriptSegment(runs: [], resultStartSec: 0, resultEndSec: 1) == nil)
    }

    @Test("transcript JSON round-trips with flags and metrics")
    func transcriptRoundTrip() throws {
        let segment = TranscriptSegment(text: "a b", startSec: 0, endSec: 1, confidence: 0.1)
        let transcript = Transcript(
            source: "clip.m4a", locale: "en_US", config: TranscriptionConfig(),
            createdAt: Date(timeIntervalSince1970: 0),
            segments: [segment], speechRegions: nil,
            metrics: TranscriptionMetrics(audioSec: 60, wallSec: 6, assetStatus: "installed"))
        #expect(transcript.segments.first?.flags == [.lowConfidence])
        #expect(transcript.metrics?.realTimeFactor == 0.1)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Transcript.self, from: transcript.jsonData()) == transcript)
    }

    @Test("real-time factor is nil for empty audio")
    func emptyRTF() {
        #expect(TranscriptionMetrics(audioSec: 0, wallSec: 1, assetStatus: "installed").realTimeFactor == nil)
    }
}
