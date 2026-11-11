import AnamnesisKit
import AVFAudio
import Foundation
import Speech

/// The Speech modules one job runs, built from a `TranscriptionConfig` (spec 003 R3). Created per job: a
/// module belongs to one analyzer.
nonisolated struct TranscriptionModules: Sendable {
    enum Transcriber: Sendable {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
    }

    let transcriber: Transcriber
    let detector: SpeechDetector?

    init(locale: Locale, config: TranscriptionConfig) {
        let attributes: Set<SpeechTranscriber.ResultAttributeOption> = [.audioTimeRange, .transcriptionConfidence]
        switch config.module {
        case .speechTranscriber(let etiquette):
            transcriber = .speech(SpeechTranscriber(
                locale: locale,
                transcriptionOptions: etiquette ? [.etiquetteReplacements] : [],
                // Final results only: volatile results are for a later live preview (spec 003 §4).
                reportingOptions: config.includeAlternatives ? [.alternativeTranscriptions] : [],
                attributeOptions: attributes))
        case .dictation(let preset):
            var options: DictationTranscriber.Preset = switch preset {
            case .longDictation: .longDictation
            case .timeIndexedLongDictation: .timeIndexedLongDictation
            }
            options.reportingOptions.remove(.volatileResults)
            if config.includeAlternatives { options.reportingOptions.insert(.alternativeTranscriptions) }
            options.attributeOptions.formUnion([.audioTimeRange, .transcriptionConfidence])
            transcriber = .dictation(DictationTranscriber(locale: locale, preset: options))
        }
        detector = config.speechDetector.map {
            let level: SpeechDetector.SensitivityLevel = switch $0 {
            case .low: .low
            case .medium: .medium
            case .high: .high
            }
            return SpeechDetector(detectionOptions: .init(sensitivityLevel: level), reportResults: true)
        }
    }

    var all: [any SpeechModule] {
        let transcriber: any SpeechModule = switch self.transcriber {
        case .speech(let module): module
        case .dictation(let module): module
        }
        return [transcriber] + (detector.map { [$0] } ?? [])
    }

    /// Asset status concerns the transcriber; the detector has no locale model.
    var transcriberOnly: [any SpeechModule] { Array(all.prefix(1)) }

    static func analyzerOptions(_ config: TranscriptionConfig) -> SpeechAnalyzer.Options {
        let priority: TaskPriority = switch config.priority {
        case .userInitiated: .userInitiated
        case .utility: .utility
        case .background: .background
        }
        let retention: SpeechAnalyzer.Options.ModelRetention = switch config.modelRetention {
        case .whileInUse: .whileInUse
        case .lingering: .lingering
        case .processLifetime: .processLifetime
        }
        return SpeechAnalyzer.Options(priority: priority, modelRetention: retention,
                                      ignoresResourceLimits: config.ignoresResourceLimits)
    }

    /// Supported-locale lookup per module family (`DictationTranscriber` has its own list).
    static func supportedLocale(equivalentTo locale: Locale, config: TranscriptionConfig) async -> Locale? {
        switch config.module {
        case .speechTranscriber: await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        case .dictation: await DictationTranscriber.supportedLocale(equivalentTo: locale)
        }
    }
}

nonisolated extension AssetInventory.Status {
    var name: String {
        switch self {
        case .unsupported: "unsupported"
        case .downloading: "downloading"
        case .supported: "supported"
        case .installed: "installed"
        @unknown default: "unknown"
        }
    }
}

nonisolated extension AVAudioFormat {
    /// e.g. "16000 Hz · 1 ch · int16 · interleaved", for metrics and FINDINGS.
    var shortDescription: String {
        let common = switch commonFormat {
        case .pcmFormatInt16: "int16"
        case .pcmFormatInt32: "int32"
        case .pcmFormatFloat32: "float32"
        case .pcmFormatFloat64: "float64"
        default: "other"
        }
        return "\(Int(sampleRate)) Hz · \(channelCount) ch · \(common) · \(isInterleaved ? "interleaved" : "planar")"
    }
}
