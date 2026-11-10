#if DEBUG
import AnamnesisKit
import AVFAudio
import Foundation
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
import Speech

// SPIKE: Gathers `DeviceEnvironmentReport`. Read-only: never triggers an asset download (spec 000 §4).
enum DeviceEnvironmentProbe {
    private static let localeSampleSize = 10

    static func makeReport() async -> DeviceEnvironmentReport {
        DeviceEnvironmentReport(
            generatedAt: Date(),
            device: .current(),
            app: .current(),
            locale: .init(current: Locale.current.identifier, preferredLanguages: Locale.preferredLanguages),
            capabilities: await capabilities()
        )
    }

    // MARK: - Capability probes

    private static func capabilities() async -> DeviceEnvironmentReport.Capabilities {
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        let speech = await speechModuleFacts(locale: locale)
        return .init(
            screenCapturePickerAvailable: screenCapturePickerAvailable(),
            speechTranscriberAvailable: SpeechTranscriber.isAvailable,
            supportedLocaleCount: supported.count,
            supportedLocalesSample: supported.prefix(localeSampleSize).map(\.identifier).sorted(),
            installedLocales: installed.map(\.identifier).sorted(),
            transcriberLocale: locale?.identifier,
            assetStatus: speech.assetStatus,
            bestAudioFormat: speech.format
        )
    }

    /// nil when the SDK has no ScreenCaptureKit (the iOS 27 simulator SDK does not ship it).
    private static func screenCapturePickerAvailable() -> Bool? {
        #if canImport(ScreenCaptureKit)
        SCContentSharingPicker.shared.isAvailable
        #else
        nil
        #endif
    }

    /// Builds a throwaway transcriber only to ask about assets and formats; nothing is analyzed.
    private static func speechModuleFacts(
        locale: Locale?
    ) async -> (assetStatus: String?, format: DeviceEnvironmentReport.AudioFormatInfo?) {
        guard let locale else { return (nil, nil) }
        let modules: [any SpeechModule] = [SpeechTranscriber(locale: locale, preset: .transcription)]
        let status = await AssetInventory.status(forModules: modules)
        // `AVAudioFormat` is not Sendable, so only plain values leave this function.
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules).map(audioFormatInfo)
        return (assetStatusName(status), format)
    }

    private static func assetStatusName(_ status: AssetInventory.Status) -> String {
        switch status {
        case .unsupported: "unsupported"
        case .downloading: "downloading"
        case .supported: "supported (not installed)"
        case .installed: "installed"
        @unknown default: "unknown"
        }
    }

    private static func audioFormatInfo(_ format: AVAudioFormat) -> DeviceEnvironmentReport.AudioFormatInfo {
        let commonFormat = switch format.commonFormat {
        case .pcmFormatFloat32: "float32"
        case .pcmFormatFloat64: "float64"
        case .pcmFormatInt16: "int16"
        case .pcmFormatInt32: "int32"
        case .otherFormat: "other"
        @unknown default: "unknown(\(format.commonFormat.rawValue))"
        }
        return .init(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            commonFormat: commonFormat,
            isInterleaved: format.isInterleaved
        )
    }
}
#endif
