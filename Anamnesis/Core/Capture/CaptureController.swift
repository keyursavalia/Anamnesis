import AnamnesisKit
import Foundation
import Observation
import UIKit

/// The process's one capture path (spec 008 R1), in Release and DEBUG. Owns the only `SCKCaptureBackend`, hence the
/// only picker observer (F-032); the control intent, the Captures screen and the Lab all drive it.
/// Also keeps the *Capture poem* control in step and writes each session's `capture.json` (R8).
@Observable
final class CaptureController {
    private(set) var lastError: String?

    private let log: AppLog
    /// `AsyncStream` has one consumer, so the backend's events are read here once and fanned out.
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<CaptureEvent>.Continuation] = [:]
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    /// The session the running capture spools into, with its record; kept past the backend clearing `spool`.
    @ObservationIgnored private var current: (session: SpoolSession, record: CaptureRecord)?
    /// Record writes run in order off the main actor.
    @ObservationIgnored private var lastRecordWrite: Task<Void, Never>?

    #if canImport(ScreenCaptureKit)
    /// nil only if Application Support is unwritable (no run folder for the report).
    let backend: SCKCaptureBackend?
    /// Used by the next start. Product defaults: spool on, raw dump off; the Lab's probe screen edits them.
    var settings = SCKCaptureBackend.Settings()
    #endif

    init(spoolDirectory: SpoolDirectory?, log: AppLog) {
        self.log = log
        // Off by default; `batteryLevel` reads −1 until it is enabled.
        UIDevice.current.isBatteryMonitoringEnabled = true
        #if canImport(ScreenCaptureKit)
        #if DEBUG
        let keepsReports = true
        #else
        // Release keeps no probe reports; this also clears runs a crash left behind (spec 014 R4).
        let keepsReports = false
        try? ProbeRunStore.appDefault().removeAll()
        #endif
        backend = (try? ProbeRunStore.appDefault()).map {
            SCKCaptureBackend(store: $0, keepsReports: keepsReports, spoolDirectory: spoolDirectory, log: log)
        }
        if backend == nil { lastError = "Application Support is not writable; capture is unavailable." }
        // For the process's lifetime, not a view's, so no event is lost on navigation.
        if let events = backend?.events {
            eventsTask = Task { [weak self] in
                for await event in events { self?.handle(event) }
            }
        }
        #endif
    }

    #if canImport(ScreenCaptureKit)
    var isCapturing: Bool { backend?.isCapturing ?? false }
    var isPickerAvailable: Bool { backend?.isPickerAvailable ?? false }
    var activeSpoolSessionID: String? { backend?.spool?.session.id }
    #else
    /// The simulator SDK has no ScreenCaptureKit: nothing ever captures.
    var isCapturing: Bool { false }
    var isPickerAvailable: Bool { false }
    var activeSpoolSessionID: String? { nil }
    #endif

    /// Every event the backend emits from now on, after the controller has handled it.
    func subscribe() -> AsyncStream<CaptureEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// Presents the system picker; capture starts when the user confirms it. Errors land in `lastError` too.
    func start(label: String? = nil, settle: Duration = .zero) throws {
        lastError = nil
        #if canImport(ScreenCaptureKit)
        if let label { settings.runLabel = label }
        guard let backend else { throw CaptureError.pickerUnavailable }
        do {
            try backend.requestStart(settings, settle: settle)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
        #else
        throw CaptureError.pickerUnavailable
        #endif
    }

    @discardableResult
    func stop() async -> ProbeRun? {
        #if canImport(ScreenCaptureKit)
        await backend?.stop()
        #else
        nil
        #endif
    }

    // MARK: - Events

    private func handle(_ event: CaptureEvent) {
        syncControl(with: event)
        switch event {
        case .started: recordStart()
        case .stopped(let run): recordStop(reason: run.report.stop?.reason.rawValue ?? "unknown")
        case .pickerFailed(let message): lastError = "Picker failed: \(message)"
        case .startFailed(let message): lastError = "Start failed: \(message)"
        case .pickerPresented, .pickerCancelled, .filterReceived: break
        }
        for subscriber in subscribers.values { subscriber.yield(event) }
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

    // MARK: - capture.json (R8)

    private func recordStart() {
        #if canImport(ScreenCaptureKit)
        guard let session = backend?.spool?.session else { return }
        let power = Self.powerSnapshot()
        let record = CaptureRecord(sessionID: session.id, startedAt: power.takenAt, start: power)
        current = (session, record)
        write(record, to: session)
        #endif
    }

    private func recordStop(reason: String) {
        guard let session = current?.session, var record = current?.record else { return }
        current = nil
        let power = Self.powerSnapshot()
        record.markStopped(at: power.takenAt, reason: reason, power: power)
        // Stopped with the app in front: the user can expect the transcript now, not at the next foreground.
        if UIApplication.shared.applicationState == .active { record.markForegrounded(at: power.takenAt) }
        log.notice("capture record session=\(session.id) durationSec=\(Int(record.durationSec ?? 0)) "
                   + "battery=\(power.batteryLevel.map { String(format: "%.2f", $0) } ?? "nil") "
                   + "thermal=\(power.thermalState)")
        write(record, to: session)
    }

    private func write(_ record: CaptureRecord, to session: SpoolSession) {
        let previous = lastRecordWrite
        let log = log
        lastRecordWrite = Task.detached {
            await previous?.value
            do {
                try record.write(to: session.captureRecordURL)
            } catch {
                log.error("capture record not written session=\(session.id): \(error.localizedDescription)")
            }
        }
    }

    static func powerSnapshot() -> PowerSnapshot {
        let device = UIDevice.current
        let level = device.batteryLevel
        let state: PowerSnapshot.BatteryState = switch device.batteryState {
        case .unplugged: .unplugged
        case .charging: .charging
        case .full: .full
        case .unknown: .unknown
        @unknown default: .unknown
        }
        return PowerSnapshot(
            takenAt: Date(), batteryLevel: level < 0 ? nil : Double(level), batteryState: state,
            thermalState: DeviceSnapshot.currentThermalStateName(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
