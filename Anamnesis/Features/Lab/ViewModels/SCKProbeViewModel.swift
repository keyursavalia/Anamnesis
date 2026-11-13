#if DEBUG && canImport(ScreenCaptureKit)
import AnamnesisKit
import Foundation
import Observation
import UIKit

// SPIKE: Lab → SCK Probe (spec 001 Step 6). Drives the app's one `CaptureController` (spec 008 R1); it has no
// backend of its own, so the Lab and the product share one picker observer (F-032).
@Observable
final class SCKProbeViewModel {
    /// The controller's settings, so a probe run and a control launch use what the operator set.
    var settings: SCKCaptureBackend.Settings {
        get { controller.settings }
        set { controller.settings = newValue }
    }
    var noteText = ""
    private(set) var live: ProbeReport?
    private(set) var liveSpool: SegmentedSpoolWriter.Progress?
    private(set) var liveLevel: ProbeReport.TimelineSecond?
    private(set) var lastRun: ProbeRun?
    private(set) var runs: [ProbeRun] = []
    private(set) var eventLines: [String] = []
    private(set) var lastError: String?

    var backend: SCKCaptureBackend? { controller.backend }
    private let controller: CaptureController
    private let store: ProbeRunStore?
    private let fileLog: FileLog?
    private let sessions: SessionIngestor?
    private var eventsTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        fileLog = environment.fileLog
        sessions = environment.sessions
        controller = environment.capture
        let store = try? ProbeRunStore.appDefault()
        self.store = store
        if store == nil { lastError = "Application Support is not writable; probe runs cannot be saved." }
        refreshRuns()
        // Observed for the model's lifetime (the app session), not a view's, so no event is lost on navigation.
        let events = controller.subscribe()
        eventsTask = Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
    }

    var isCapturing: Bool { controller.isCapturing }
    var isPickerAvailable: Bool { controller.isPickerAvailable }

    func start(settle: Duration = .zero) {
        lastError = nil
        do {
            try controller.start(settle: settle)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        if let run = await controller.stop() { lastRun = run }
        refreshRuns()
    }

    /// DEBUG: abandon the spool mid-capture, stop, and run recovery as the next launch would.
    func simulateCrash() async {
        if let run = await backend?.simulateSpoolCrash() { lastRun = run }
        refreshRuns()
        append("spool abandoned (simulated crash); recovering")
        await sessions?.refresh(activeSessionIDs: [])
    }

    func mark(_ kind: ProbeReport.MarkerKind) {
        let text = kind == .note ? noteText.trimmingCharacters(in: .whitespaces) : nil
        backend?.addMarker(kind, text: text?.isEmpty == true ? nil : text)
        append("marker \(kind.rawValue)\(text.map { ": \($0)" } ?? "")")
        if kind == .note { noteText = "" }
    }

    /// Adds a note marker without touching the operator's note field (spec 005 trigger timings).
    func addNote(_ text: String) {
        backend?.addMarker(.note, text: text)
        append("marker note: \(text)")
    }

    func refreshRuns() {
        runs = store?.listRuns() ?? []
    }

    /// Polls cheap counters at 2 Hz while the screen is visible (spec 001 §4.7).
    func pollLive() async {
        while !Task.isCancelled {
            live = backend?.recorder?.snapshot(includingSeries: false)
            liveLevel = backend?.recorder?.liveLevel()
            liveSpool = backend?.spool?.progressSnapshot()
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    func copyLog() {
        UIPasteboard.general.string = fileLog?.snapshot() ?? "(no file log)"
    }

    /// Writes the file log to a temp file for `ShareLink`.
    func exportLogURL() -> URL? {
        guard let fileLog else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "anamnesis-log.txt")
        return (try? fileLog.export(to: url)) == nil ? nil : url
    }

    // MARK: - Private

    /// The controller has already synced the control and written the capture record.
    private func handle(_ event: CaptureEvent) {
        switch event {
        case .pickerPresented(let style): append("picker presented (\(style))")
        case .pickerCancelled: append("picker cancelled")
        case .pickerFailed(let message):
            lastError = "Picker failed: \(message)"
            append("picker failed: \(message)")
        case .filterReceived(let unsolicited, let existing):
            append("filter received" + (unsolicited ? " — UNSOLICITED (system UI)" : "")
                   + (existing ? " for existing stream" : ""))
        case .started: append("capture started")
        case .startFailed(let message):
            lastError = "Start failed: \(message)"
            append("start failed: \(message)")
        case .stopped(let run):
            lastRun = run
            if let stop = run.report.stop, stop.reason != .user {
                lastError = "Stopped (\(stop.reason.rawValue)): \(stop.errorDescription ?? "no error")"
            }
            append("stopped: \(run.report.stop?.reason.rawValue ?? "?")")
            refreshRuns()
        }
    }

    private func append(_ line: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        eventLines.insert("\(time)  \(line)", at: 0)
        if eventLines.count > 30 { eventLines.removeLast() }
    }
}
#endif
