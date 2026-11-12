/// Line-break quality (TESTING §4.4, spec 004 R4). A break is "after reference word i"; hypothesis breaks are
/// mapped onto reference positions through the WER alignment, so wrong words do not shift the score.
public struct LineBreakScore: Sendable, Equatable, Codable {
    public var truthBreaks: Int
    public var predictedBreaks: Int
    public var matched: Int

    /// nil when nothing was predicted.
    public var precision: Double? { predictedBreaks > 0 ? Double(matched) / Double(predictedBreaks) : nil }
    /// nil when the truth has no breaks.
    public var recall: Double? { truthBreaks > 0 ? Double(matched) / Double(truthBreaks) : nil }
    public var f1: Double? { // swiftlint:disable:this identifier_name
        guard let precision, let recall else { return nil }
        return precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
    }
}

public enum LineBreakScorer {
    /// Any newline run (line or stanza) is one break. Lines that normalize to no words are ignored, as is a
    /// break after the last word.
    public static func score(reference: String, hypothesis: String, tolerance: Int = 1) -> LineBreakScore {
        let (refWords, refBreaks) = wordsAndBreaks(reference)
        let (hypWords, hypBreaks) = wordsAndBreaks(hypothesis)
        let alignment = WER.align(reference: refWords, hypothesis: hypWords).alignment
        var mapped: [Int] = []
        var consumed = 0
        for step in alignment {
            if step.reference != nil { consumed += 1 }
            if let index = step.hypothesisIndex, hypBreaks.contains(index) { mapped.append(consumed - 1) }
        }
        return score(truthBreaks: refBreaks.sorted(), predictedBreaks: mapped, tolerance: tolerance)
    }

    /// One-to-one matching within ±`tolerance` positions. Greedy over sorted positions is optimal for this.
    public static func score(truthBreaks: [Int], predictedBreaks: [Int], tolerance: Int = 1) -> LineBreakScore {
        let truth = truthBreaks.sorted()
        var next = 0
        var matched = 0
        for predicted in predictedBreaks.sorted() {
            while next < truth.count, truth[next] < predicted - tolerance { next += 1 }
            if next < truth.count, truth[next] <= predicted + tolerance {
                matched += 1
                next += 1
            }
        }
        return LineBreakScore(truthBreaks: truth.count, predictedBreaks: predictedBreaks.count, matched: matched)
    }

    /// Normalized words, and the indices of words that end a line (excluding the final word).
    static func wordsAndBreaks(_ text: String) -> ([String], Set<Int>) {
        var words: [String] = []
        var breaks: Set<Int> = []
        for line in text.split(whereSeparator: \.isNewline) {
            let lineWords = TextNormalizer.words(String(line))
            guard !lineWords.isEmpty else { continue }
            words += lineWords
            breaks.insert(words.count - 1)
        }
        breaks.remove(words.count - 1)
        return (words, breaks)
    }
}
