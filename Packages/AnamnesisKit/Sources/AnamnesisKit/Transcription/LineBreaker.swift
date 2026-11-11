public struct LineBreakConfig: Sendable, Equatable, Codable {
    /// Pause that ends a line. 0.6 s is the ARCHITECTURE §5.3 proposal `[HYPOTHESIS]`.
    public var lineGap: Double
    /// Pause that ends a stanza (blank line). 1.5 s proposal `[HYPOTHESIS]`.
    public var stanzaGap: Double

    public init(lineGap: Double = 0.6, stanzaGap: Double = 1.5) {
        self.lineGap = lineGap
        self.stanzaGap = stanzaGap
    }
}

/// Infers poem layout from transcriber results and pauses (spec 003 R7, amended by D-024).
public enum LineBreaker {
    /// Words joined by a space, a newline (gap ≥ `lineGap`) or a blank line (gap ≥ `stanzaGap`).
    /// Gaps are measured from the latest end so far, so overlapping timings never produce a break.
    public static func format(_ words: [TranscriptWord], config: LineBreakConfig = LineBreakConfig()) -> String {
        var text = ""
        var lastEnd: Double?
        for word in words.sorted(by: { $0.startSec < $1.startSec }) {
            if let lastEnd {
                let gap = word.startSec - lastEnd
                text += gap >= config.stanzaGap ? "\n\n" : gap >= config.lineGap ? "\n" : " "
            }
            text += word.text
            lastEnd = max(lastEnd ?? word.endSec, word.endSec)
        }
        return text
    }

    /// D-024: each transcriber result is at least one line, because `SpeechTranscriber` word timings are
    /// contiguous (F-020) and its pauses fall between results. Results ≥ `stanzaGap` apart start a stanza.
    public static func format(_ segments: [TranscriptSegment], config: LineBreakConfig = LineBreakConfig()) -> String {
        var text = ""
        var lastEnd: Double?
        for segment in segments.sorted(by: { $0.startSec < $1.startSec }) {
            if let lastEnd { text += segment.startSec - lastEnd >= config.stanzaGap ? "\n\n" : "\n" }
            text += format(segment.timedTokens, config: config)
            lastEnd = max(lastEnd ?? segment.endSec, segment.endSec)
        }
        return text
    }
}
