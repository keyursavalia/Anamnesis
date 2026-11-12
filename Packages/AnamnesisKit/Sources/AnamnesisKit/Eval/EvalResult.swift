import Foundation

/// R5: how much text the transcriber produced where there is no speech (category M).
public struct HallucinationMetric: Sendable, Equatable, Codable {
    /// Seconds covered by non-empty results per minute of audio.
    public var textSecondsPerMinute: Double
    public var flaggedSegments: Int
}

public struct EvalScores: Sendable, Equatable, Codable {
    /// nil without a truth file, or with an empty one (category M).
    public var wer: WERResult?
    public var cer: Double?
    /// Only for truths with ≥ 4 lines (TESTING §4.4).
    public var lineBreaks: LineBreakScore?
    /// Only for category M clips.
    public var hallucination: HallucinationMetric?
    public var flaggedSegments: Int
}

/// One clip × config job (spec 004 R2).
public struct EvalResult: Sendable, Equatable, Codable {
    public var clipID: String
    public var category: String?
    public var configName: String
    public var finishedAt: Date
    public var transcript: Transcript?
    public var scores: EvalScores?
    /// Set when the job failed; the run continues with the next job.
    public var error: String?

    public init(clipID: String, category: String?, configName: String, finishedAt: Date, transcript: Transcript?,
                scores: EvalScores?, error: String?) {
        self.clipID = clipID
        self.category = category
        self.configName = configName
        self.finishedAt = finishedAt
        self.transcript = transcript
        self.scores = scores
        self.error = error
    }
}

/// R8 (TESTING §4.6): 5 perfect · 4 a few fixes (< 2 min) · 3 significant · 2 easier to retype · 1 unusable.
public struct EvalRating: Sendable, Equatable, Codable {
    public var clipID: String
    public var configName: String
    public var rating: Int
    public var minutesToFix: Double?
    public var ratedAt: Date

    public init(clipID: String, configName: String, rating: Int, minutesToFix: Double?, ratedAt: Date) {
        self.clipID = clipID
        self.configName = configName
        self.rating = min(5, max(1, rating))
        self.minutesToFix = minutesToFix
        self.ratedAt = ratedAt
    }

    /// "Fixable" = rating ≥ 4.
    public var isFixable: Bool { rating >= 4 }
}

public enum EvalScoring {
    public static func score(transcript: Transcript, truth: String?, isHallucinationClip: Bool,
                             lineBreaks: LineBreakConfig) -> EvalScores {
        let flagged = transcript.segments.filter { !$0.flags.isEmpty }.count
        let hasTruthText = !(truth.map(TextNormalizer.words) ?? []).isEmpty
        var scores = EvalScores(flaggedSegments: flagged)
        if let truth, hasTruthText {
            scores.wer = WER.score(reference: truth, hypothesis: transcript.plainText)
            scores.cer = WER.cer(reference: truth, hypothesis: transcript.plainText)
            if LineBreakScorer.wordsAndBreaks(truth).1.count >= 3 {
                scores.lineBreaks = LineBreakScorer.score(reference: truth,
                                                          hypothesis: transcript.poemText(config: lineBreaks))
            }
        }
        if isHallucinationClip {
            let textSeconds = transcript.segments.map(\.segment.durationSec).reduce(0, +)
            let minutes = (transcript.metrics?.audioSec ?? 0) / 60
            scores.hallucination = HallucinationMetric(textSecondsPerMinute: minutes > 0 ? textSeconds / minutes : 0,
                                                       flaggedSegments: flagged)
        }
        return scores
    }
}

/// The resumable state file of one batch run (spec 004 R2): configs × clips, finished results and ratings.
public struct EvalRun: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var device: DeviceSnapshot
    /// CFBundleShortVersionString (CFBundleVersion). The git commit is not embedded in the build.
    public var appVersion: String
    public var sweep: String
    public var configs: [ExperimentConfig]
    public var clips: [CorpusClip]
    public var results: [EvalResult]
    public var ratings: [EvalRating]

    public init(id: String, createdAt: Date, device: DeviceSnapshot, appVersion: String, sweep: String,
                configs: [ExperimentConfig], clips: [CorpusClip]) {
        self.id = id
        self.createdAt = createdAt
        self.device = device
        self.appVersion = appVersion
        self.sweep = sweep
        self.configs = configs
        self.clips = clips
        results = []
        ratings = []
    }

    public struct Job: Sendable, Equatable {
        public var clip: CorpusClip
        public var config: ExperimentConfig
    }

    /// Config-major order, so a partial run already compares complete configs. Failed jobs count as done.
    public var pendingJobs: [Job] {
        let done = Set(results.map { "\($0.configName)\u{1F}\($0.clipID)" })
        return configs.flatMap { config in
            clips.filter { !done.contains("\(config.name)\u{1F}\($0.id)") }.map { Job(clip: $0, config: config) }
        }
    }

    public var totalJobs: Int { configs.count * clips.count }

    public func result(clipID: String, configName: String) -> EvalResult? {
        results.last { $0.clipID == clipID && $0.configName == configName }
    }

    public func rating(clipID: String, configName: String) -> EvalRating? {
        ratings.last { $0.clipID == clipID && $0.configName == configName }
    }

    /// Replaces an earlier rating for the same clip × config.
    public mutating func setRating(_ rating: EvalRating) {
        ratings.removeAll { $0.clipID == rating.clipID && $0.configName == rating.configName }
        ratings.append(rating)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> EvalRun {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvalRun.self, from: data)
    }
}
