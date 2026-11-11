import Foundation
import Speech

/// Domain errors for asset management and transcription jobs (spec 003 R9). Speech codes keep their number so
/// exported reports can be matched against APPLE_APIS §1.8.
nonisolated enum TranscriptionError: Error, LocalizedError, Equatable {
    case transcriberUnavailable
    case unsupportedLocale(String)
    /// `AssetInventory.status` was not `.installed` when a job started.
    case modelNotInstalled(status: String)
    case fileUnreadable(String)
    case cancelled
    /// An `SFSpeechError` code; `name` is ours for the codes this SDK documents.
    case speech(code: Int, name: String, message: String)
    case other(domain: String, code: Int, message: String)

    init(_ error: any Error) {
        if let error = error as? TranscriptionError {
            self = error
        } else if error is CancellationError {
            self = .cancelled
        } else if let error = error as? SFSpeechError {
            self = .speech(code: error.code.rawValue, name: Self.name(of: error.code),
                           message: error.localizedDescription)
        } else {
            let error = error as NSError
            self = .other(domain: error.domain, code: error.code, message: error.localizedDescription)
        }
    }

    var speechCode: SFSpeechError.Code? {
        if case .speech(let code, _, _) = self { SFSpeechError.Code(rawValue: code) } else { nil }
    }

    var errorDescription: String? {
        switch self {
        case .transcriberUnavailable: "SpeechTranscriber is not available on this device"
        case .unsupportedLocale(let locale): "Locale \(locale) is not supported for transcription"
        case .modelNotInstalled(let status): "Speech model not installed (status: \(status)); install it in the Lab"
        case .fileUnreadable(let detail): "Cannot read audio: \(detail)"
        case .cancelled: "Transcription cancelled"
        case .speech(let code, let name, let message): "Speech error \(code) (\(name)): \(message)"
        case .other(let domain, let code, let message): "\(domain) \(code): \(message)"
        }
    }

    private static func name(of code: SFSpeechError.Code) -> String {
        let known: [(SFSpeechError.Code, String)] = [
            (.audioDisordered, "audioDisordered"),
            (.unexpectedAudioFormat, "unexpectedAudioFormat"),
            (.noModel, "noModel"),
            (.assetLocaleNotAllocated, "assetLocaleNotAllocated"),
            (.tooManyAssetLocalesAllocated, "tooManyAssetLocalesAllocated"),
            (.incompatibleAudioFormats, "incompatibleAudioFormats"),
            (.moduleOutputFailed, "moduleOutputFailed"),
            (.cannotAllocateUnsupportedLocale, "cannotAllocateUnsupportedLocale"),
            (.insufficientResources, "insufficientResources"),
            (.cannotConfigureAudioSystem, "cannotConfigureAudioSystem")
        ]
        return known.first { $0.0 == code }?.1 ?? "unknown"
    }
}
