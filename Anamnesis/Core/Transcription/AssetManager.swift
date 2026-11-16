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

    /// Known to be missing, downloading, or stuck offline: recordings wait for it (spec 020 R7).
    var isAwaitingInstall: Bool {
        switch self {
        case .status(let status): status != .installed && status != .unsupported
        case .installing, .failed: true
        case .unknown, .transcriberUnavailable, .unsupportedLocale: false
        }
    }

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }

    /// The welcome's ring (spec 020 R7): 0…1, with a sliver showing before any progress.
    var setupProgress: Double {
        switch self {
        case .status(.installed): 1
        case .installing(let fraction): max(0.03, fraction)
        default: 0.03
        }
    }

    /// One line for a person, not the Lab: where the one-time download stands.
    var setupDetail: String {
        switch self {
        case .status(.installed): "Ready"
        case .installing(let fraction): "Downloading · \(Int(fraction * 100)) %"
        case .status(.downloading): "Downloading…"
        case .failed: "Waiting for internet · it will retry on its own"
        case .transcriberUnavailable, .unsupportedLocale, .status(.unsupported): "Not available on this device"
        case .unknown, .status: "Checking…"
        }
    }

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
    /// The one install in flight, so the welcome, the queue and Settings never start two.
    @ObservationIgnored private var installTask: Task<Void, Never>?

    init(log: AppLog) {
        self.log = log
    }

    /// Spec 020 R7: makes sure the model is on the device, from the welcome or whenever the app comes forward.
    /// Already installed, or an install running: returns at once (or waits for that install). Otherwise the system
    /// downloads it (the app's only tolerated network use, invariant 1). Offline, it fails quietly and the next
    /// activation tries again.
    func ensureInstalled(locale: Locale, config: TranscriptionConfig) async {
        if let installTask { return await installTask.value }
        // Set before the first `await`, so a second caller joins this one instead of starting its own.
        let task = Task {
            await refresh(locale: locale, config: config)
            guard case .status(let status) = state, status == .supported || status == .downloading else { return }
            await install(locale: locale, config: config)
        }
        installTask = task
        await task.value
        installTask = nil
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
            // Stopped before the refresh: left running through its `await`s, the poller could overwrite
            // `.installed` with `.installing(1.0)`, so waiting recordings never started (review B2).
            poller.cancel()
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
