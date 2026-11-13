#if DEBUG && canImport(ScreenCaptureKit)
import AnamnesisKit
import Foundation
import Observation
import UIKit

// SPIKE: Lab → SCK Probe (spec 001 Step 6).
@Observable
final class SCKProbeViewModel {
    var settings = SCKCaptureBackend.Settings()
    var noteText = ""
    private(set) var live: ProbeReport?
    private(set) var liveSpool: SegmentedSpoolWriter.Progress?
    private(set) var liveLevel: ProbeReport.TimelineSecond?
    private(set) var lastRun: ProbeRun?
    private(set) var runs: [ProbeRun] = []
    private(set) var eventLines: [String] = []
    private(set) var lastError: String?

    let backend: SCKCaptureBackend?
    private let store: ProbeRunStore?
    private let fileLog: FileLog?
    private let sessions: SessionIngestor?
    private let log: AppLog
    private var eventsTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        fileLog = environment.fileLog
        log = environment.log(.capture)
        sessions = environment.sessions
        let store = try? ProbeRunStore.appDefault()
        self.store = store
        backend = store.map {
            SCKCaptureBackend(
                store: $0, spoolDirectory: environment.sessions?.directory, log: environment.log(.capture))
        }
        if store == nil { lastError = "Application Support is not writable; probe runs cannot be saved." }
        refreshRuns()
        // Observed for the model's lifetime (the app session), not a view's, so no event is lost on navigation.
        if let events = backend?.events {
            eventsTask = Task { [weak self] in
                for await event in events { self?.handle(event) }
            }
        }
    }

    var isCapturing: Bool { backend?.isCapturing ?? false }
    var isPickerAvailable: Bool { backend?.isPickerAvailable ?? false }

    func start(settle: Duration = .zero) {
        lastError = nil
        do {
            try backend?.requestStart(settings, settle: settle)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        if let run = await backend?.stop() { lastRun = run }
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

    private func handle(_ event: CaptureEvent) {
        syncControl(with: event)
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
            Task { await sessions?.refresh(activeSessionIDs: []) }
        }
    }

    /// Keeps the *Capture poem* control in step with the stream, whichever way it started or ended (spec 005 Step 6).
    private func syncControl(with event: CaptureEvent) {
        switch event {
        case .started:
            CaptureControlSync.publish(CaptureControlState(isCapturing: true, startedAt: Date()), log: log)
        case .pickerCancelled, .pickerFailed, .startFailed, .stopped:
            CaptureControlSync.publish(.idle, log: log)
        case .pickerPresented, .filterReceived:
            break
        }
    }

    private func append(_ line: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        eventLines.insert("\(time)  \(line)", at: 0)
        if eventLines.count > 30 { eventLines.removeLast() }
    }
}
#endif
