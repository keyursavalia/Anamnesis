#if DEBUG
import Foundation

// SPIKE: Lab environment report (spec 000 R6/R7). Exported as JSON to `TestResults/R-<id>_env.json`.
nonisolated struct DeviceEnvironmentReport: Codable, Sendable {
    struct Device: Codable, Sendable {
        var modelIdentifier: String
        var osVersion: String
        var osBuild: String
        var thermalState: String
        var lowPowerModeEnabled: Bool
        var physicalMemoryBytes: UInt64
        var isSimulator: Bool
    }

    struct App: Codable, Sendable {
        var bundleID: String
        var version: String
        var build: String
    }

    struct LocaleInfo: Codable, Sendable {
        var current: String
        var preferredLanguages: [String]
    }

    struct AudioFormatInfo: Codable, Sendable {
        var sampleRate: Double
        var channelCount: UInt32
        var commonFormat: String
        var isInterleaved: Bool
    }

    struct Capabilities: Codable, Sendable {
        /// `SCContentSharingPicker.shared.isAvailable` (iOS 27); nil where ScreenCaptureKit is absent (simulator).
        var screenCapturePickerAvailable: Bool?
        var speechTranscriberAvailable: Bool
        var supportedLocaleCount: Int
        /// First few supported locales; the full list is long and not useful in a report.
        var supportedLocalesSample: [String]
        var installedLocales: [String]
        /// `SpeechTranscriber.supportedLocale(equivalentTo: .current)`; nil if the current locale is unsupported.
        var transcriberLocale: String?
        /// `AssetInventory.status(forModules:)` for a transcriber on `transcriberLocale`.
        var assetStatus: String?
        /// `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` for that transcriber.
        var bestAudioFormat: AudioFormatInfo?
    }

    var generatedAt: Date
    var device: Device
    var app: App
    var locale: LocaleInfo
    var capabilities: Capabilities

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
#endif
