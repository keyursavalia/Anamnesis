import Foundation

/// One timed token of a transcript (spec 003 R5). Seconds are on the job's timeline (session offset included).
public struct TranscriptWord: Sendable, Equatable, Codable {
    public var text: String
    public var startSec: Double
    public var endSec: Double
    /// `transcriptionConfidence` (0…1) when the module reported it.
    public var confidence: Double?

    public init(text: String, startSec: Double, endSec: Double, confidence: Double? = nil) {
        self.text = text
        self.startSec = startSec
        self.endSec = endSec
        self.confidence = confidence
    }
}

/// One attributed run of a Speech result, copied into plain values. The app extracts these from the result's
/// `AttributedString` (Speech is not importable here); `TranscriptSegment(runs:)` is the pure mapping.
public struct TranscriptRun: Sendable, Equatable {
    public var text: String
    /// nil when the run has no `audioTimeRange` (e.g. inter-word whitespace).
    public var startSec: Double?
    public var endSec: Double?
    public var confidence: Double?

    public init(text: String, startSec: Double? = nil, endSec: Double? = nil, confidence: Double? = nil) {
        self.text = text
        self.startSec = startSec
        self.endSec = endSec
        self.confidence = confidence
    }
}

/// One final result of the transcriber, flattened (spec 003 R5).
public struct TranscriptSegment: Sendable, Equatable, Codable {
    public var text: String
    public var startSec: Double
    public var endSec: Double
    /// Mean of the word confidences; nil when none was reported.
    public var confidence: Double?
    /// nil when the module reported no per-run time ranges.
    public var words: [TranscriptWord]?

    public init(text: String, startSec: Double, endSec: Double, confidence: Double? = nil,
                words: [TranscriptWord]? = nil) {
        self.text = text
        self.startSec = startSec
        self.endSec = endSec
        self.confidence = confidence
        self.words = words
    }

    /// Builds a segment from a result's runs. `resultStartSec`/`resultEndSec` (the result's `range`) are the
    /// fallback span when no run carries a time range. Returns nil for a result that is only whitespace.
    public init?(runs: [TranscriptRun], resultStartSec: Double, resultEndSec: Double) {
        let text = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let words = runs.compactMap { run -> TranscriptWord? in
            let token = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, let start = run.startSec, let end = run.endSec else { return nil }
            return TranscriptWord(text: token, startSec: start, endSec: end, confidence: run.confidence)
        }
        let confidences = runs.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap(\.confidence)
        self.init(
            text: text,
            startSec: words.map(\.startSec).min() ?? resultStartSec,
            endSec: words.map(\.endSec).max() ?? resultEndSec,
            confidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count),
            words: words.isEmpty ? nil : words)
    }

    public var durationSec: Double { max(0, endSec - startSec) }

    /// Words if timed, otherwise the whole segment as one pseudo-word (for line-break inference).
    public var timedTokens: [TranscriptWord] {
        words ?? [TranscriptWord(text: text, startSec: startSec, endSec: endSec, confidence: confidence)]
    }
}

/// A `SpeechDetector` result as plain values.
public struct SpeechRegion: Sendable, Equatable, Codable {
    public var startSec: Double
    public var endSec: Double
    public var speechDetected: Bool

    public init(startSec: Double, endSec: Double, speechDetected: Bool) {
        self.startSec = startSec
        self.endSec = endSec
        self.speechDetected = speechDetected
    }
}
