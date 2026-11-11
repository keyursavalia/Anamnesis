import AnamnesisKit
import Foundation
import Observation
import Speech

/// Speech model state for one locale + module choice (spec 003 R1).
enum AssetState: Equatable {
    case unknown
    case transcriberUnavailable
    case unsupportedLocale
    /// `AssetInventory.Status` as reported; `.supported` means "downloadable, not installed".
    case status(AssetInventory.Status)
    case installing(fraction: Double)
    case failed(String)

    var isInstalled: Bool { self == .status(.installed) }

    var label: String {
        switch self {
        case .unknown: "Checking…"
        case .transcriberUnavailable: "SpeechTranscriber unavailable on this device"
        case .unsupportedLocale: "Locale not supported"
        case .status(let status): status == .supported ? "Not installed (downloadable)" : status.name.capitalized
        case .installing(let fraction): "Installing \(Int(fraction * 100)) %"
        case .failed(let message): "Failed: \(message)"
        }
    }
}

/// Checks and installs the on-device speech model. The OS downloads it once: this is the app's only tolerated
/// network use (CLAUDE.md invariant 1), performed by the system, not by our code.
@Observable
final class AssetManager {
    private(set) var state: AssetState = .unknown
    private(set) var supportedLocales: [Locale] = []
    private(set) var installedLocaleIDs: Set<String> = []

    private let log: AppLog

    init(log: AppLog) {
        self.log = log
    }

    func loadLocales() async {
        supportedLocales = await SpeechTranscriber.supportedLocales
            .sorted { $0.identifier < $1.identifier }
        installedLocaleIDs = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
    }

    func refresh(locale: Locale, config: TranscriptionConfig) async {
        state = await Self.currentState(locale: locale, config: config)
        log.notice("asset status locale=\(locale.identifier) module=\(config.module) state=\(state.label)")
    }

    func install(locale: Locale, config: TranscriptionConfig) async {
        guard let resolved = await TranscriptionModules.supportedLocale(equivalentTo: locale, config: config) else {
            state = .unsupportedLocale
            return
        }
        let modules = TranscriptionModules(locale: resolved, config: config).transcriberOnly
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
                await refresh(locale: resolved, config: config)
                return
            }
            log.notice("asset install started locale=\(resolved.identifier)")
            state = .installing(fraction: 0)
            // SPIKE: polling is simpler than KVO under Swift 6 and is only for the Lab progress bar.
            let progress = request.progress
            let poller = Task { [weak self] in
                while !Task.isCancelled {
                    self?.state = .installing(fraction: progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { poller.cancel() }
            try await request.downloadAndInstall()
            log.notice("asset install finished locale=\(resolved.identifier)")
            await refresh(locale: resolved, config: config)
            await loadLocales()
        } catch {
            let mapped = TranscriptionError(error)
            log.error("asset install failed locale=\(resolved.identifier) \(mapped.localizedDescription)")
            state = .failed(mapped.localizedDescription)
        }
    }

    nonisolated static func currentState(locale: Locale, config: TranscriptionConfig) async -> AssetState {
        guard SpeechTranscriber.isAvailable else { return .transcriberUnavailable }
        guard let resolved = await TranscriptionModules.supportedLocale(equivalentTo: locale, config: config) else {
            return .unsupportedLocale
        }
        let modules = TranscriptionModules(locale: resolved, config: config).transcriberOnly
        return .status(await AssetInventory.status(forModules: modules))
    }
}
