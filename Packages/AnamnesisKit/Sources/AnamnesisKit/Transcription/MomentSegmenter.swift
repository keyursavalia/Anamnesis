/// A run of speech worth reviewing as one candidate poem (spec 003 R6, ARCHITECTURE §5.3).
public struct Moment: Sendable, Equatable, Codable {
    public var startSec: Double
    public var endSec: Double
    public var segments: [TranscriptSegment]

    public init(startSec: Double, endSec: Double, segments: [TranscriptSegment]) {
        self.startSec = startSec
        self.endSec = endSec
        self.segments = segments
    }

    public var text: String { segments.map(\.text).joined(separator: " ") }
    public var durationSec: Double { max(0, endSec - startSec) }
}

public struct MomentConfig: Sendable, Equatable, Codable {
    /// Segments closer than this are one Moment. 3 s is the ARCHITECTURE §5.3 proposal `[HYPOTHESIS]`.
    public var momentGap: Double

    public init(momentGap: Double = 3.0) {
        self.momentGap = momentGap
    }
}

public enum MomentSegmenter {
    /// Groups segments (sorted by start) into Moments, splitting wherever the silence between the end of
    /// everything so far and the next segment is ≥ `momentGap`. Overlapping segments always merge.
    public static func moments(from segments: [TranscriptSegment], config: MomentConfig = MomentConfig()) -> [Moment] {
        var moments: [Moment] = []
        for segment in segments.sorted(by: { $0.startSec < $1.startSec }) {
            if var last = moments.last, segment.startSec - last.endSec < config.momentGap {
                last.segments.append(segment)
                last.endSec = max(last.endSec, segment.endSec)
                moments[moments.count - 1] = last
            } else {
                moments.append(Moment(startSec: segment.startSec, endSec: segment.endSec, segments: [segment]))
            }
        }
        return moments
    }
}
