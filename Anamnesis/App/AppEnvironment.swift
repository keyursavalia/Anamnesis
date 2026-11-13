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
    /// The one capture path (spec 008 R1): the control, the Captures screen and the Lab all use it.
    let capture: CaptureController
    /// nil when there is no spool directory (nothing to transcribe).
    let transcripts: TranscriptionQueue?
    /// Sessions, Moments and poems (spec 009).
    let library: LibraryStore
    /// `Application Support`; nil only if it is unavailable.
    let supportDirectory: URL?
    /// Set when *Delete all data* finishes; the root view returns to Captures (spec 013 R3).
    var dataDeletedAt: Date?
    @ObservationIgnored private var launchObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var captureEventsTask: Task<Void, Never>?

    /// One per process, created at `App.init`, so an intent run in a cold background launch finds it ready, and a
    /// second instance can never register a second picker observer (F-032, H1/H3). Previews make their own.
    static let shared = AppEnvironment()
    private static var instanceCount = 0

    init() {
        Self.instanceCount += 1
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        supportDirectory = support
        let fileLog: FileLog?
        do {
            guard let support else { throw CocoaError(.fileNoSuchFile) }
            fileLog = try FileLog(directory: support.appending(path: "Logs"))
        } catch {
            Logger(category: .ui).error("FileLog unavailable: \(error.localizedDescription, privacy: .public)")
            fileLog = nil
        }
        self.fileLog = fileLog
        let sessions = support.map {
            SessionIngestor(directory: SpoolDirectory(root: $0.appending(path: "Spool")),
                            log: AppLog(category: .spool, fileLog: fileLog))
        }
        self.sessions = sessions
        let capture = CaptureController(
            spoolDirectory: sessions?.directory, log: AppLog(category: .capture, fileLog: fileLog))
        self.capture = capture
        let library = LibraryStore(directory: support, log: AppLog(category: .ui, fileLog: fileLog))
        self.library = library
        transcripts = sessions.map {
            TranscriptionQueue(sessions: $0, library: library, capture: capture,
                               log: AppLog(category: .transcribe, fileLog: fileLog))
        }
        log(.ui).notice("AppEnvironment init #\(Self.instanceCount)")
        // Nothing captures in a fresh process; clears a state left by a capture the app died in.
        CaptureControlSync.publish(.idle, log: log(.ui))
        observeLaunchMailbox()
        observeCapture()
    }

    func log(_ category: LogCategory) -> AppLog {
        AppLog(category: category, fileLog: fileLog)
    }

    /// Launch, foreground and capture stop: recover sessions the app died in, except the one being written now,
    /// bring the library store up to date (spec 009), then let the queue transcribe what is waiting (spec 008 R4).
    func refreshSessions() async {
        guard let sessions else { return }
        await sessions.refresh(activeSessionIDs: activeSpoolSessionIDs)
        await library.sync(with: sessions.sessions, log: log(.ui))
        await transcripts?.sessionsDidRefresh()
    }

    // MARK: - Data (spec 013)

    enum DataError: LocalizedError {
        case capturing

        var errorDescription: String? { "Stop the capture first." }
    }

    struct StorageUsage: Sendable {
        var captures: Int64
        var library: Int64
        var diagnostics: Int64
    }

    /// Sizes for Settings, read off the main actor.
    func storageUsage() async -> StorageUsage? {
        guard let support = supportDirectory else { return nil }
        return await Task.detached {
            StorageUsage(
                captures: AppDataFiles.size(of: support.appending(path: "Spool")),
                library: LibraryStore.files(in: support).reduce(0) { $0 + AppDataFiles.size(of: $1) },
                diagnostics: AppDataFiles.size(of: support.appending(path: "Logs"))
                    + AppDataFiles.size(of: support.appending(path: "Probes")))
        }.value
    }

    /// *Delete all data* (R3): the library, every spool session, probe reports, exports and the log. The log is
    /// cleared last so nothing from before survives; the next event starts a new one.
    func deleteAllData() async throws {
        guard !capture.isCapturing else { throw DataError.capturing }
        log(.ui).notice("delete all data")
        await transcripts?.suspendForDeletion()
        defer { transcripts?.resume() }
        try library.deleteAll()
        if let support = supportDirectory {
            for name in ["Spool", "Probes"] { try AppDataFiles.removeContents(of: support.appending(path: name)) }
        }
        try AppDataFiles.removeContents(of: FileManager.default.temporaryDirectory)
        await sessions?.refresh(activeSessionIDs: [])
        fileLog?.clear()
        dataDeletedAt = Date()
    }

    /// The latest control/deep-link launch (spec 005); the capture screen reacts when it changes.
    var launchRequest: LaunchRequest?
    /// Set by `anamnesis://session?id=` (spec 008 R9); the Captures screen opens it and clears it.
    var openSessionID: String?

    func open(_ url: URL) {
        if let link = SessionLink(url: url) {
            log(.ui).notice("open session \(link.sessionID)")
            openSessionID = link.sessionID
        } else if let link = CaptureLaunchLink(url: url) {
            receive(link, via: "url")
        } else {
            log(.ui).error("ignored URL: \(url.absoluteString)")
        }
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
        if link.rung == .withoutForeground { presentPickerWithoutForeground() }
    }

    /// A capture start frees the analyzer; a stop saves the session and, with the app in front, transcribes it.
    private func observeCapture() {
        let events = capture.subscribe()
        captureEventsTask = Task { [weak self] in
            for await event in events {
                switch event {
                case .started: self?.transcripts?.pauseForCapture()
                case .stopped: await self?.refreshSessions()
                default: break
                }
            }
        }
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
        if capture.isCapturing {
            log(.capture).notice("control: stop requested")
            let task = UIApplication.shared.beginBackgroundTask(withName: "capture-stop")
            Task {
                await capture.stop()
                UIApplication.shared.endBackgroundTask(task)
            }
            return
        }
        // Nothing to stop: the switch showed a stale "on", because the system ignores the app's reload after a stop
        // from the recording indicator (F-037). The user tapped a switch for a capture that is not running, so
        // start one; the reload at start is honoured because it follows the tap.
        receive(CaptureLaunchLink(rung: .withoutForeground, tappedAt: Date()), via: "intent (switch was stale)")
    }

    /// The system honours a control reload while the app is in front (F-037); refreshes a switch left stale.
    func reloadControl() {
        CaptureControlSync.reload(log: log(.ui))
    }

    var isCapturing: Bool { capture.isCapturing }

    private var activeSpoolSessionIDs: Set<String> {
        Set([capture.activeSpoolSessionID].compactMap(\.self))
    }

    /// Rung 3, cold, windowless or suspended (F-036). Logs the app state so a run shows it really was not in front.
    private func presentPickerWithoutForeground() {
        guard !capture.isCapturing else {
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
        try? capture.start(label: "launch-rung3", settle: settle)
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
    /// One probe screen model per app session; it drives `capture` and has no backend of its own.
    @ObservationIgnored private var sckProbeModel: SCKProbeViewModel?

    func sckProbe() -> SCKProbeViewModel {
        if let sckProbeModel { return sckProbeModel }
        let model = SCKProbeViewModel(environment: self)
        sckProbeModel = model
        return model
    }
    #endif
}
