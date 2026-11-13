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
        // Nothing captures in a fresh process; clears a state left by a capture the app died in.
        CaptureControlSync.publish(.idle, log: log(.ui))
        observeLaunchMailbox()
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

    /// Picks up a command the control's intent posted in-process (F-028); call on each post and on becoming active.
    func drainLaunchMailbox() {
        switch CaptureLaunchMailbox.shared.take() {
        case .start(let link): receive(link, via: "intent")
        case .stop: stopCaptureFromControl()
        case nil: break
        }
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
    }

    /// The control was switched off. The app may be in the background, so keep it running until the run is saved.
    private func stopCaptureFromControl() {
        #if DEBUG && canImport(ScreenCaptureKit)
        if let model = sckProbeModel, model.isCapturing {
            log(.capture).notice("control: stop requested")
            let task = UIApplication.shared.beginBackgroundTask(withName: "capture-stop")
            Task {
                await model.stop()
                UIApplication.shared.endBackgroundTask(task)
            }
            return
        }
        #endif
        // Nothing to stop: the switch showed a stale "on", because the system ignores the app's reload after a stop
        // from the recording indicator (F-037). The user tapped a switch for a capture that is not running, so
        // start one; the reload at start is honoured because it follows the tap.
        receive(CaptureLaunchLink(rung: .withoutForeground, tappedAt: Date()), via: "intent (switch was stale)")
    }

    /// The system honours a control reload while the app is in front (F-037); refreshes a switch left stale.
    func reloadControl() {
        CaptureControlSync.reload(log: log(.ui))
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

    /// Rung 3, cold, windowless or suspended (F-036). Logs the app state so a run shows it really was not in front.
    private func presentPickerWithoutForeground() {
        let model = sckProbe()
        guard !model.isCapturing else {
            // The switch showed a stale "off" while capturing: show the truth instead of starting a second capture.
            CaptureControlSync.publish(CaptureControlState(isCapturing: true), log: log(.capture))
            return
        }
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
