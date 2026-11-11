/// What a transcription job runs (spec 003 R3), as plain Codable values so it can travel into exported reports.
/// The app maps it onto Speech types; nothing here imports Speech.
public struct TranscriptionConfig: Sendable, Equatable, Codable {
    public enum Module: Sendable, Equatable, Codable {
        /// `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)`.
        case speechTranscriber(etiquetteReplacements: Bool)
        /// `DictationTranscriber` with a preset's options (Step 8 comparison wiring).
        case dictation(DictationPreset)
    }

    public enum DictationPreset: String, Sendable, Codable, CaseIterable {
        case longDictation
        case timeIndexedLongDictation
    }

    public enum Sensitivity: String, Sendable, Codable, CaseIterable {
        case low, medium, high
    }

    public enum Priority: String, Sendable, Codable, CaseIterable {
        case userInitiated, utility, background
    }

    public enum ModelRetention: String, Sendable, Codable, CaseIterable {
        case whileInUse, lingering, processLifetime
    }

    public var module: Module
    /// nil = no `SpeechDetector` in the analyzer.
    public var speechDetector: Sensitivity?
    public var includeAlternatives: Bool
    public var priority: Priority
    public var modelRetention: ModelRetention
    /// iOS 27 `SpeechAnalyzer.Options.ignoresResourceLimits`; only for the background probe (ARCHITECTURE §5.4).
    public var ignoresResourceLimits: Bool

    /// R3 default: `SpeechTranscriber`, no options, final results only, time ranges + confidence.
    public init(module: Module = .speechTranscriber(etiquetteReplacements: false), speechDetector: Sensitivity? = nil,
                includeAlternatives: Bool = false, priority: Priority = .userInitiated,
                modelRetention: ModelRetention = .lingering, ignoresResourceLimits: Bool = false) {
        self.module = module
        self.speechDetector = speechDetector
        self.includeAlternatives = includeAlternatives
        self.priority = priority
        self.modelRetention = modelRetention
        self.ignoresResourceLimits = ignoresResourceLimits
    }
}
