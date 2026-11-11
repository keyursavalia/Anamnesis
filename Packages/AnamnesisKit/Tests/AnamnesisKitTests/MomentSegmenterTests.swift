import Testing
@testable import AnamnesisKit

@Suite("MomentSegmenter")
struct MomentSegmenterTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        /// (start, end) per segment.
        let spans: [(Double, Double)]
        /// Number of segments in each expected Moment.
        let expected: [Int]
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "empty", spans: [], expected: []),
        Case(name: "single segment", spans: [(0, 2)], expected: [1]),
        Case(name: "gap below momentGap merges", spans: [(0, 2), (4.9, 6)], expected: [2]),
        Case(name: "gap exactly momentGap splits", spans: [(0, 2), (5, 6)], expected: [1, 1]),
        Case(name: "huge gap splits", spans: [(0, 1), (600, 601)], expected: [1, 1]),
        Case(name: "overlap merges", spans: [(0, 5), (4, 6)], expected: [2]),
        Case(name: "unsorted input is ordered", spans: [(10, 11), (0, 1), (1.5, 2)], expected: [2, 1]),
        Case(name: "gap measured from latest end", spans: [(0, 10), (1, 2), (12, 13)], expected: [3])
    ]

    @Test("groups segments by silence", arguments: cases)
    func grouping(_ testCase: Case) {
        let segments = testCase.spans.map { TranscriptSegment(text: "x", startSec: $0.0, endSec: $0.1) }
        let moments = MomentSegmenter.moments(from: segments, config: MomentConfig(momentGap: 3))
        #expect(moments.map(\.segments.count) == testCase.expected)
    }

    @Test("moment span and text cover its segments")
    func spanAndText() throws {
        let segments = [TranscriptSegment(text: "one", startSec: 1, endSec: 2),
                        TranscriptSegment(text: "two", startSec: 2.5, endSec: 4)]
        let moment = try #require(MomentSegmenter.moments(from: segments).first)
        #expect(moment.startSec == 1)
        #expect(moment.endSec == 4)
        #expect(moment.text == "one two")
        #expect(moment.durationSec == 3)
    }
}
