import Foundation

/// Per-job instrumentation (spec 003 R10).
public struct TranscriptionMetrics: Sendable, Equatable, Codable {
    public var audioSec: Double
    public var wallSec: Double
    /// `AssetInventory.Status` before the job, e.g. "installed".
    public var assetStatus: String
    /// Highest `phys_footprint` sampled during the job; the model itself runs out of process (ARCHITECTURE §5.4).
    public var peakFootprintMB: Double?
    /// `SpeechAnalyzer.bestAvailableAudioFormat`, for AC7.
    public var analyzerFormat: String?

    public init(audioSec: Double, wallSec: Double, assetStatus: String, peakFootprintMB: Double? = nil,
                analyzerFormat: String? = nil) {
        self.audioSec = audioSec
        self.wallSec = wallSec
        self.assetStatus = assetStatus
        self.peakFootprintMB = peakFootprintMB
        self.analyzerFormat = analyzerFormat
    }

    /// Wall time per second of audio: < 1 is faster than real time. nil for empty audio.
    public var realTimeFactor: Double? { audioSec > 0 ? wallSec / audioSec : nil }
}

/// The exported result of one job: everything the Lab shows, as JSON.
public struct Transcript: Sendable, Equatable, Codable {
    public struct FlaggedSegment: Sendable, Equatable, Codable {
        public var segment: TranscriptSegment
        public var flags: [HallucinationFlag]
    }

    public var source: String
    public var locale: String
    public var config: TranscriptionConfig
    public var createdAt: Date
    public var segments: [FlaggedSegment]
    /// nil when the job ran without `SpeechDetector`.
    public var speechRegions: [SpeechRegion]?
    public var metrics: TranscriptionMetrics?

    public init(source: String, locale: String, config: TranscriptionConfig, createdAt: Date,
                segments: [TranscriptSegment], speechRegions: [SpeechRegion]?, metrics: TranscriptionMetrics?,
                hallucinationConfig: HallucinationConfig = HallucinationConfig()) {
        self.source = source
        self.locale = locale
        self.config = config
        self.createdAt = createdAt
        self.segments = segments.map {
            FlaggedSegment(segment: $0, flags: HallucinationHeuristics
                .flags(for: $0, speechRegions: speechRegions, config: hallucinationConfig)
                .sorted { $0.rawValue < $1.rawValue })
        }
        self.speechRegions = speechRegions
        self.metrics = metrics
    }

    public var plainText: String { segments.map(\.segment.text).joined(separator: " ") }

    public func poemText(config: LineBreakConfig = LineBreakConfig()) -> String {
        LineBreaker.format(segments.map(\.segment), config: config)
    }

    public func moments(config: MomentConfig = MomentConfig()) -> [Moment] {
        MomentSegmenter.moments(from: segments.map(\.segment), config: config)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
