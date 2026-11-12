import AnamnesisKit
import Foundation
import Observation
import os
import UIKit

/// Dependency container injected via `.environment`. Services are added here as specs introduce them.
@Observable
final class AppEnvironment {
    /// nil only if Application Support is unwritable; logging then falls back to `os.Logger` alone.
    let fileLog: FileLog?
    /// nil only if Application Support is unavailable; capture then runs without spooling.
    let sessions: SessionIngestor?
    @ObservationIgnored private var launchObserver: (any NSObjectProtocol)?
    /// Last time a scene became active; logged by the rung-3 check.
    @ObservationIgnored private var lastActiveAt: Date?

    /// One per process, created at `App.init`, so an intent run in a cold background launch finds it ready, and a
    /// second instance can never register a second picker observer (F-032, H1/H3). Previews make their own.
    static let shared = AppEnvironment()
    private static var instanceCount = 0

    init() {
        Self.instanceCount += 1
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileLog: FileLog?
        do {
            guard let support else { throw CocoaError(.fileNoSuchFile) }
            fileLog = try FileLog(directory: support.appending(path: "Logs"))
        } catch {
            Logger(category: .ui).error("FileLog unavailable: \(error.localizedDescription, privacy: .public)")
            fileLog = nil
        }
        self.fileLog = fileLog
        sessions = support.map {
            SessionIngestor(directory: SpoolDirectory(root: $0.appending(path: "Spool")),
                            log: AppLog(category: .spool, fileLog: fileLog))
        }
        log(.ui).notice("AppEnvironment init #\(Self.instanceCount)")
        observeLaunchMailbox()
    }

    func markActive() {
        lastActiveAt = Date()
    }

    func log(_ category: LogCategory) -> AppLog {
        AppLog(category: category, fileLog: fileLog)
    }

    /// Launch and foreground: recover sessions the app died in, except the one being written now.
    func refreshSessions() async {
        await sessions?.refresh(activeSessionIDs: activeSpoolSessionIDs)
    }

    /// The latest control/deep-link launch (spec 005); the Lab navigates to the capture screen when it changes.
    var launchRequest: LaunchRequest?

    func open(_ url: URL) {
        guard let link = CaptureLaunchLink(url: url) else {
            log(.ui).error("ignored URL: \(url.absoluteString)")
            return
        }
        receive(link, via: "url")
    }

    /// Picks up a link the control's intent posted in-process (F-028); call on each post and on becoming active.
    func drainLaunchMailbox() {
        if let link = CaptureLaunchMailbox.shared.take() { receive(link, via: "intent") }
    }

    private func receive(_ link: CaptureLaunchLink, via source: String) {
        launchRequest = LaunchRequest(link: link)
        log(.ui).notice("launch \(source) rung=\(link.rung.rawValue) tappedAt=\(link.tappedAt?.description ?? "nil")")
        #if DEBUG && canImport(ScreenCaptureKit)
        if link.rung == .withoutForeground { presentPickerWithoutForeground() }
        #endif
    }

    /// Observes the mailbox here rather than in a view: a background intent (rung 3) may run with no scene built.
    private func observeLaunchMailbox() {
        launchObserver = NotificationCenter.default.addObserver(
            forName: CaptureLaunchMailbox.didPost, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.drainLaunchMailbox() }
        }
        drainLaunchMailbox()
        let log = log(.capture)
        CaptureLaunchMailbox.shared.setInPlaceCheck { [weak self] in
            await MainActor.run { Self.canPresentPickerInPlace(log: log, lastActiveAt: self?.lastActiveAt) }
        }
    }

    /// A suspended app keeps its scene and presents in place reliably (F-034). A cold background launch for an intent
    /// has no scene; F-031 suggested `present()` then waits for the next launch, but that run had the F-032 bugs.
    /// SPIKE (F-034 cold experiment): always try in place and log the scenes; fallback to rung 2 is off.
    private static func canPresentPickerInPlace(log: AppLog, lastActiveAt: Date?) -> Bool {
        let scenes = UIApplication.shared.connectedScenes
        // activationState: 0 foregroundActive, 1 foregroundInactive, 2 background, -1 unattached.
        let states = scenes.map { String($0.activationState.rawValue) }.joined(separator: ",")
        let sinceActive = lastActiveAt.map { String(format: "%.0f s", Date().timeIntervalSince($0)) } ?? "never"
        log.notice("rung 3 check: applicationState=\(UIApplication.shared.applicationState.rawValue) "
                   + "scenes=[\(states)] sinceActive=\(sinceActive)")
        return true
    }

    var isCapturing: Bool {
        #if DEBUG && canImport(ScreenCaptureKit)
        sckProbeModel?.isCapturing ?? false
        #else
        false
        #endif
    }

    private var activeSpoolSessionIDs: Set<String> {
        #if DEBUG && canImport(ScreenCaptureKit)
        Set([sckProbeModel?.backend?.spool?.session.id].compactMap(\.self))
        #else
        []
        #endif
    }

    #if DEBUG
    /// One per app session so a running job survives navigating away from the Lab screen.
    @ObservationIgnored private var transcriptionLabModel: TranscriptionLabViewModel?
    @ObservationIgnored private var evalModel: EvalViewModel?

    func transcriptionLab() -> TranscriptionLabViewModel {
        if let transcriptionLabModel { return transcriptionLabModel }
        let model = TranscriptionLabViewModel(environment: self)
        transcriptionLabModel = model
        return model
    }

    func evalLab() -> EvalViewModel {
        if let evalModel { return evalModel }
        let model = EvalViewModel(environment: self)
        evalModel = model
        return model
    }
    #endif

    #if DEBUG && canImport(ScreenCaptureKit)
    /// One probe per app session: a capture keeps running while the operator navigates the Lab,
    /// and only one observer is ever registered with the system picker.
    @ObservationIgnored private var sckProbeModel: SCKProbeViewModel?

    func sckProbe() -> SCKProbeViewModel {
        if let sckProbeModel { return sckProbeModel }
        let model = SCKProbeViewModel(environment: self)
        sckProbeModel = model
        return model
    }

    // SPIKE: rung 3. Records the app state so the log shows whether we really were not in the foreground.
    private func presentPickerWithoutForeground() {
        let model = sckProbe()
        guard !model.isCapturing else { return }
        let state = UIApplication.shared.applicationState
        let cold = UIApplication.shared.connectedScenes.isEmpty
        // Longer settle when cold: the picker observer was registered only just now.
        let settle: Duration = cold ? .seconds(1) : .milliseconds(500)
        // applicationState: 0 active, 1 inactive, 2 background.
        log(.capture).notice("rung 3: requesting picker, applicationState=\(state.rawValue) cold=\(cold)")
        launchRequest?.startRequestedAt = Date()
        model.settings.runLabel = "launch-rung3"
        model.start(settle: settle)
    }
    #endif
}
