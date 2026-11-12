import Foundation

/// Why a segment looks like model output rather than speech (spec 003 R8). Flags only; nothing is deleted.
public enum HallucinationFlag: String, Sendable, Codable, CaseIterable {
    /// The same n-gram repeats back to back (a decoding loop).
    case repeatedNGramLoop
    /// Mean confidence below `HallucinationConfig.minConfidence`.
    case lowConfidence
    /// `SpeechDetector` found speech in too little of the segment's span.
    case noSpeechOverlap
}

/// All thresholds are `[HYPOTHESIS]` until Test B (spec 004) supplies real distributions.
public struct HallucinationConfig: Sendable, Equatable, Codable {
    public var minConfidence: Double
    /// A loop needs this many back-to-back repeats of one n-gram…
    public var minRepeats: Int
    /// …covering at least this many tokens, so "never, never" or a short refrain is not flagged.
    public var minLoopTokens: Int
    public var maxNGram: Int
    /// Fraction of the segment span that must overlap detected speech.
    public var minSpeechCoverage: Double

    public init(minConfidence: Double = 0.2, minRepeats: Int = 3, minLoopTokens: Int = 6, maxNGram: Int = 6,
                minSpeechCoverage: Double = 0.2) {
        self.minConfidence = minConfidence
        self.minRepeats = minRepeats
        self.minLoopTokens = minLoopTokens
        self.maxNGram = maxNGram
        self.minSpeechCoverage = minSpeechCoverage
    }
}

public enum HallucinationHeuristics {
    /// `speechRegions` nil or empty means the detector was off or reported nothing: the overlap check is
    /// skipped, not failed.
    public static func flags(for segment: TranscriptSegment, speechRegions: [SpeechRegion]?,
                             config: HallucinationConfig = HallucinationConfig()) -> Set<HallucinationFlag> {
        var flags: Set<HallucinationFlag> = []
        if hasRepeatedNGramLoop(tokens(of: segment.text), config: config) { flags.insert(.repeatedNGramLoop) }
        if let confidence = segment.confidence, confidence < config.minConfidence { flags.insert(.lowConfidence) }
        if let speechRegions, !speechRegions.isEmpty,
           speechCoverage(of: segment, in: speechRegions) < config.minSpeechCoverage {
            flags.insert(.noSpeechOverlap)
        }
        return flags
    }

    /// Lower-cased words without punctuation.
    static func tokens(of text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(["'"]).inverted)
            .filter { !$0.isEmpty }
    }

    static func hasRepeatedNGramLoop(_ tokens: [String], config: HallucinationConfig) -> Bool {
        guard config.minRepeats >= 2, config.maxNGram >= 1 else { return false }
        for size in 1...config.maxNGram {
            let repeatsNeeded = max(config.minRepeats, (config.minLoopTokens + size - 1) / size)
            guard size * repeatsNeeded <= tokens.count else { continue }
            for start in 0...(tokens.count - size * repeatsNeeded) {
                let gram = tokens[start..<(start + size)]
                let repeated = (1..<repeatsNeeded).allSatisfy { index in
                    tokens[(start + index * size)..<(start + (index + 1) * size)] == gram
                }
                if repeated { return true }
            }
        }
        return false
    }

    /// Fraction (0…1) of the segment span covered by speech-detected regions. A zero-length segment counts as
    /// covered if any speech region contains its instant.
    static func speechCoverage(of segment: TranscriptSegment, in regions: [SpeechRegion]) -> Double {
        let speech = regions.filter(\.speechDetected)
        guard segment.durationSec > 0 else {
            return speech.contains { $0.startSec <= segment.startSec && segment.startSec <= $0.endSec } ? 1 : 0
        }
        // Merge first so overlapping detector results are not counted twice.
        var merged: [(start: Double, end: Double)] = []
        for region in speech.sorted(by: { $0.startSec < $1.startSec }) {
            if let last = merged.last, region.startSec <= last.end {
                merged[merged.count - 1].end = max(last.end, region.endSec)
            } else {
                merged.append((region.startSec, region.endSec))
            }
        }
        let covered = merged.reduce(0.0) { total, region in
            total + max(0, min(region.end, segment.endSec) - max(region.start, segment.startSec))
        }
        return min(1, covered / segment.durationSec)
    }
}
