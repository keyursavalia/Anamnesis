/// One configuration of a Test B run (spec 004 R6, TESTING §4.5).
public struct ExperimentConfig: Sendable, Equatable, Codable, Identifiable {
    /// R10 / D-006: what the clip is re-encoded to before transcription.
    public enum AudioFormat: String, Sendable, Codable, CaseIterable {
        /// The clip as imported ("native").
        case original
        case pcm16kMono
        case pcm24kMono
        case pcm48kMono

        public var sampleRate: Double? {
            switch self {
            case .original: nil
            case .pcm16kMono: 16_000
            case .pcm24kMono: 24_000
            case .pcm48kMono: 48_000
            }
        }
    }

    public var name: String
    public var locale: String
    public var transcription: TranscriptionConfig
    public var audioFormat: AudioFormat
    public var lineBreaks: LineBreakConfig

    public var id: String { name }

    public init(name: String, locale: String = "en_US", transcription: TranscriptionConfig = TranscriptionConfig(),
                audioFormat: AudioFormat = .original, lineBreaks: LineBreakConfig = LineBreakConfig()) {
        self.name = name
        self.locale = locale
        self.transcription = transcription
        self.audioFormat = audioFormat
        self.lineBreaks = lineBreaks
    }

    /// D-018 default: SpeechTranscriber, clip as imported.
    public static let baseline = ExperimentConfig(name: "baseline")
}

/// One dimension at a time (TESTING §4.5). Each sweep includes the baseline so it is self-contained.
/// Not wired: `fastResults`/volatile (final results only by design) and `contextualStrings` (§4.5 items 4, 5).
public enum ExperimentSweep: String, Sendable, Codable, CaseIterable {
    case baselineOnly = "Baseline only"
    case format = "Format A/B"
    case module = "Module A/B"
    case detector = "Detector on/off"
    case locale = "Locale"

    public var configs: [ExperimentConfig] {
        let base = ExperimentConfig.baseline
        switch self {
        case .baselineOnly:
            return [base]
        case .format:
            return [base] + [ExperimentConfig.AudioFormat.pcm16kMono, .pcm24kMono, .pcm48kMono].map {
                ExperimentConfig(name: "format-\($0.rawValue)", audioFormat: $0)
            }
        case .module:
            return [base] + TranscriptionConfig.DictationPreset.allCases.map {
                ExperimentConfig(name: "dictation-\($0.rawValue)",
                                 transcription: TranscriptionConfig(module: .dictation($0)))
            }
        case .detector:
            return [base, ExperimentConfig(name: "detector-medium",
                                           transcription: TranscriptionConfig(speechDetector: .medium))]
        case .locale:
            return [base] + ["en_GB", "en_IN", "en_AU"].map { ExperimentConfig(name: "locale-\($0)", locale: $0) }
        }
    }
}
