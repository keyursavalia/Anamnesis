import Foundation
import Testing
@testable import AnamnesisKit

@Suite("Eval scoring and report")
struct EvalReportTests {
    static func transcript(_ segments: [TranscriptSegment], audioSec: Double = 60, wallSec: Double = 1) -> Transcript {
        Transcript(source: "clip", locale: "en_US", config: TranscriptionConfig(),
                   createdAt: Date(timeIntervalSince1970: 0), segments: segments, speechRegions: nil,
                   metrics: TranscriptionMetrics(audioSec: audioSec, wallSec: wallSec, assetStatus: "installed"))
    }

    static let poem = "do not go gentle\ninto that good night\nold age should burn\nand rave at close of day"

    @Test("scores WER on plain text and line breaks on the poem layout")
    func scoring() throws {
        let segments = ["do not go gentle", "into that good night", "old age should burn", "and rave at close of day"]
            .enumerated().map { TranscriptSegment(text: $1, startSec: Double($0) * 3, endSec: Double($0) * 3 + 2) }
        let scores = EvalScoring.score(transcript: Self.transcript(segments), truth: Self.poem,
                                       isHallucinationClip: false, lineBreaks: LineBreakConfig())
        #expect(scores.wer?.wer == 0)
        #expect(scores.cer == 0)
        let breaks = try #require(scores.lineBreaks)
        #expect(breaks.f1 == 1)
        #expect(scores.hallucination == nil)
    }

    @Test("short truths get no line-break score; empty truth gets no WER")
    func skips() {
        let transcript = Self.transcript([TranscriptSegment(text: "a b", startSec: 0, endSec: 1)])
        let short = EvalScoring.score(transcript: transcript, truth: "a\nb\nc", isHallucinationClip: false,
                                      lineBreaks: LineBreakConfig())
        #expect(short.lineBreaks == nil)
        #expect(short.wer != nil)
        let empty = EvalScoring.score(transcript: transcript, truth: "", isHallucinationClip: true,
                                      lineBreaks: LineBreakConfig())
        #expect(empty.wer == nil)
    }

    @Test("hallucination metric: text seconds per audio minute")
    func hallucination() {
        let transcript = Self.transcript([TranscriptSegment(text: "ghost", startSec: 0, endSec: 3),
                                          TranscriptSegment(text: "words", startSec: 10, endSec: 13)], audioSec: 120)
        let scores = EvalScoring.score(transcript: transcript, truth: "", isHallucinationClip: true,
                                       lineBreaks: LineBreakConfig())
        #expect(scores.hallucination == HallucinationMetric(textSecondsPerMinute: 3, flaggedSegments: 0))
    }

    static func run() -> EvalRun {
        let clips = [CorpusClip(id: "a1", clipFile: "a1.m4a", truthFile: "a1.txt", category: "A"),
                     CorpusClip(id: "b1", clipFile: "b1.m4a", truthFile: "b1.txt", category: "B"),
                     CorpusClip(id: "b2", clipFile: "b2.m4a", truthFile: "b2.txt", category: "B")]
        return EvalRun(id: "r", createdAt: Date(timeIntervalSince1970: 0), device: DeviceSnapshot.current(),
                       appVersion: "1.0 (1)", sweep: "test", configs: ExperimentSweep.detector.configs, clips: clips)
    }

    static func result(_ clip: String, _ category: String, _ config: String, wer reference: String,
                       _ hypothesis: String) -> EvalResult {
        let transcript = transcript([TranscriptSegment(text: hypothesis, startSec: 0, endSec: 1)], wallSec: 6)
        let scores = EvalScoring.score(transcript: transcript, truth: reference, isHallucinationClip: false,
                                       lineBreaks: LineBreakConfig())
        return EvalResult(clipID: clip, category: category, configName: config, finishedAt: .now,
                          transcript: transcript, scores: scores, error: nil)
    }

    @Test("pending jobs are config-major and skip finished or failed jobs")
    func pending() {
        var run = Self.run()
        #expect(run.totalJobs == 6)
        run.results.append(Self.result("a1", "A", "baseline", wer: "a", "a"))
        run.results.append(EvalResult(clipID: "b1", category: "B", configName: "baseline", finishedAt: .now,
                                      transcript: nil, scores: nil, error: "boom"))
        #expect(run.pendingJobs.map { "\($0.config.name)/\($0.clip.id)" }
                == ["baseline/b2", "detector-medium/a1", "detector-medium/b1", "detector-medium/b2"])
    }

    @Test("summaries: median, mean, min, max per category, failures and fixable share")
    func summaries() throws {
        var run = Self.run()
        run.results = [Self.result("a1", "A", "baseline", wer: "a b c d", "a b c d"),
                       Self.result("b1", "B", "baseline", wer: "a b c d", "a b c x"),
                       Self.result("b2", "B", "baseline", wer: "a b c d", "a b x x"),
                       EvalResult(clipID: "a1", category: "A", configName: "detector-medium", finishedAt: .now,
                                  transcript: nil, scores: nil, error: "boom")]
        run.setRating(EvalRating(clipID: "b1", configName: "baseline", rating: 2, minutesToFix: 5, ratedAt: .now))
        run.setRating(EvalRating(clipID: "b1", configName: "baseline", rating: 4, minutesToFix: 1, ratedAt: .now))
        run.setRating(EvalRating(clipID: "b2", configName: "baseline", rating: 3, minutesToFix: nil, ratedAt: .now))
        let summaries = EvalReport.summaries(run)
        #expect(summaries.map { "\($0.configName)/\($0.category)" }
                == ["baseline/all", "baseline/A", "baseline/B", "detector-medium/all", "detector-medium/A"])
        let all = try #require(summaries.first)
        #expect(all.wer == EvalSummary.Stats([0, 0.25, 0.5]))
        #expect(all.wer?.median == 0.25)
        #expect(all.realTimeFactor?.median == 0.1)
        #expect(all.fixableShare == 0.5)
        let b = try #require(summaries[2].wer) // swiftlint:disable:this identifier_name
        #expect(b.median == 0.375)
        #expect(b.min == 0.25 && b.max == 0.5 && b.count == 2)
        #expect(summaries[3].failures == 1 && summaries[3].wer == nil)
        #expect(run.ratings.count == 2) // the second b1 rating replaced the first
    }

    @Test("CSV escapes fields and has one row per job")
    func csv() {
        var run = Self.run()
        run.results = [Self.result("a1", "A", "baseline", wer: "a b", "a c")]
        run.results.append(EvalResult(clipID: "b1", category: "B", configName: "baseline", finishedAt: .now,
                                      transcript: nil, scores: nil, error: "Speech error 3, \"noModel\""))
        let lines = EvalReport.werCSV(run).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("a1,A,baseline,0.5000,"))
        #expect(lines[2].hasSuffix(",\"Speech error 3, \"\"noModel\"\"\""))
        #expect(EvalReport.ratingsCSV(run) == "clip,config,rating,minutes_to_fix,fixable,rated_at\n")
    }

    @Test("run state round-trips through JSON")
    func roundTrip() throws {
        var run = Self.run()
        run.results = [Self.result("a1", "A", "baseline", wer: "a b", "a c")]
        run.setRating(EvalRating(clipID: "a1", configName: "baseline", rating: 9, minutesToFix: 0.5,
                                 ratedAt: Date(timeIntervalSince1970: 10)))
        #expect(run.ratings.first?.rating == 5) // clamped to 1…5
        var decoded = try EvalRun.decode(run.jsonData())
        // ISO 8601 drops sub-second precision; compare the rest.
        decoded.results[0].finishedAt = run.results[0].finishedAt
        decoded.results[0].transcript?.createdAt = run.results[0].transcript?.createdAt ?? .now
        #expect(decoded == run)
    }
}
