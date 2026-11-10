#if canImport(ScreenCaptureKit)
import AnamnesisKit
import Foundation
import ScreenCaptureKit

// SPIKE: Probe A — ScreenCaptureKit in the host app (spec 001 §4.2). Measures and spools (spec 002); does not
// transcribe.
@Observable
final class SCKCaptureBackend: SystemAudioCapturing {
    /// Knobs the operator varies between runs; recorded in the report's `config`.
    struct Settings {
        var runLabel = ""
        var style: SCKPickerCoordinator.Style = .systemDefault
        /// 0 leaves SCK's default.
        var sampleRate = 16_000
        /// 0 leaves SCK's default.
        var channelCount = 1
        /// Hypothesis: a stream may need a `.screen` output before it delivers audio (spec 001 §4.2 step 3).
        var addScreenOutput = false
        /// Smallest frame size to keep video cost negligible; record what SCK accepts.
        var width = 2
        var height = 2
        var rawDump = false
        /// Write the session to the segmented spool (spec 002).
        var spool = true
    }

    private struct Session {
        let stream: SCStream
        let output: SCKStreamOutput
        let recorder: DiagnosticsRecorder
        let rawDump: RawDumpSink?
        let spool: SegmentedSpoolWriter?
        let context: CaptureContextObserver
        let flushTimer: DispatchSourceTimer
        let directory: URL
        let reportURL: URL
    }

    let backend = ProbeReport.Backend.screenCaptureKit
    let events: AsyncStream<CaptureEvent>
    private(set) var isCapturing = false
    /// Live counters for the Lab UI; nil when idle.
    private(set) var recorder: DiagnosticsRecorder?
    /// Live spool progress for the Lab UI; nil when idle or not spooling.
    private(set) var spool: SegmentedSpoolWriter?

    private let eventSink: AsyncStream<CaptureEvent>.Continuation
    private let coordinator = SCKPickerCoordinator()
    private let store: ProbeRunStore
    private let spoolDirectory: SpoolDirectory?
    private let log: AppLog
    private var settings = Settings()
    private var awaitingPicker = false
    /// Set while our own Stop is in flight: SCK may report -3817 for it, which must not be recorded as a system stop.
    private var isStoppingByRequest = false
    private var session: Session?

    init(store: ProbeRunStore, spoolDirectory: SpoolDirectory?, log: AppLog) {
        self.store = store
        self.spoolDirectory = spoolDirectory
        self.log = log
        (events, eventSink) = AsyncStream.makeStream(of: CaptureEvent.self)
        coordinator.onOutcome = { [weak self] outcome in self?.handle(outcome) }
        coordinator.activate()
    }

    var isPickerAvailable: Bool { coordinator.isAvailable }

    /// Presents the system picker; capture starts when it returns a filter.
    func requestStart(_ settings: Settings) throws {
        guard session == nil else { throw CaptureError.alreadyCapturing }
        guard coordinator.isAvailable else { throw CaptureError.pickerUnavailable }
        self.settings = settings
        awaitingPicker = true
        coordinator.present(settings.style)
        log.notice("picker presented style=\(settings.style.rawValue)")
        eventSink.yield(.pickerPresented(style: settings.style.rawValue))
    }

    func addMarker(_ kind: ProbeReport.MarkerKind, text: String? = nil) {
        recorder?.addMarker(kind, text: text)
    }

    func stop() async -> ProbeRun? {
        guard let session, !isStoppingByRequest else { return nil }
        isStoppingByRequest = true
        defer { isStoppingByRequest = false }
        do {
            try await session.stream.stopCapture()
        } catch {
            let error = error as NSError
            session.recorder.recordError(
                domain: error.domain, code: error.code, description: error.localizedDescription)
        }
        return await finish(session, stop: ProbeReport.Stop(reason: .user))
    }

    /// DEBUG *Simulate crash* (spec 002 R10): abandon the spool without finalizing, then stop as usual so the
    /// session is left for recovery while the probe report is still written.
    func simulateSpoolCrash() async -> ProbeRun? {
        guard let session else { return nil }
        if let spool = session.spool {
            await Task.detached { spool.abandon() }.value
            log.notice("spool abandoned (simulated crash) session=\(spool.session.id)")
        }
        return await stop()
    }

    // MARK: - Picker outcomes

    private func handle(_ outcome: SCKPickerCoordinator.Outcome) {
        switch outcome {
        case .filter(let filter, let forExistingStream):
            let unsolicited = !awaitingPicker
            awaitingPicker = false
            log.notice("filter received unsolicited=\(unsolicited) existingStream=\(forExistingStream) "
                       + "style=\(filter.style.rawValue) rect=\(filter.contentRect)")
            eventSink.yield(.filterReceived(unsolicited: unsolicited, forExistingStream: forExistingStream))
            // iOS cannot retarget a running stream (`updateContentFilter` is unavailable), so ignore it.
            guard session == nil else { return }
            let style = unsolicited ? "systemUI" : settings.style.rawValue
            Task { await startStream(filter: filter, styleUsed: style) }
        case .cancelled:
            awaitingPicker = false
            log.notice("picker cancelled")
            eventSink.yield(.pickerCancelled)
        case .failed(let message):
            awaitingPicker = false
            log.error("picker failed: \(message)")
            eventSink.yield(.pickerFailed(message))
        }
    }

    // MARK: - Stream lifecycle

    private func startStream(filter: SCContentFilter, styleUsed: String) async {
        let label = settings.runLabel
        let directory: URL
        do {
            directory = try store.makeRunDirectory(label: label, startedAt: Date())
        } catch {
            eventSink.yield(.startFailed(CaptureError.storage(error.localizedDescription).localizedDescription))
            return
        }
        let spool = settings.spool ? makeSpool(label: label) : nil
        var config = reportConfig(styleUsed: styleUsed, filter: filter)
        config.spoolSessionID = spool?.session.id
        let recorder = DiagnosticsRecorder(
            runLabel: label, backend: backend, config: config, device: .current(), app: .current())
        let rawDump = settings.rawDump ? try? RawDumpSink(directory: directory) : nil
        let output = SCKStreamOutput(
            pipeline: AudioIngestPipeline(recorder: recorder, rawDump: rawDump, spool: spool),
            onStop: { [weak self] stop in Task { @MainActor in await self?.handleStreamStopped(stop) } })
        let stream = SCStream(filter: filter, configuration: streamConfiguration(), delegate: output)
        let reportURL = store.reportURL(in: directory, label: label, backend: backend)
        let session = Session(
            stream: stream, output: output, recorder: recorder, rawDump: rawDump, spool: spool,
            context: CaptureContextObserver(recorder: recorder),
            flushTimer: Self.makeFlushTimer(recorder: recorder, store: store, reportURL: reportURL),
            directory: directory, reportURL: reportURL)
        self.session = session
        self.recorder = recorder
        self.spool = spool
        do {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.sampleQueue)
            if settings.addScreenOutput {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.sampleQueue)
            }
            try await stream.startCapture()
        } catch {
            let error = error as NSError
            let description = "\(StreamErrorCode.name(error.code)) (\(error.domain) \(error.code)): "
                + error.localizedDescription
            log.error("start failed: \(description)")
            eventSink.yield(.startFailed(description))
            _ = await finish(session, stop: ProbeReport.Stop(
                reason: .error, errorDomain: error.domain, errorCode: error.code, errorDescription: description))
            return
        }
        session.flushTimer.resume()
        isCapturing = true
        log.notice("capture started style=\(styleUsed)")
        eventSink.yield(.started)
    }

    /// The system ended the stream (user stopped via the indicator, background mode missing, …).
    private func handleStreamStopped(_ stop: ProbeReport.Stop) async {
        guard let session, !isStoppingByRequest else { return }
        log.error("stream stopped by system: \(stop.errorDescription ?? stop.reason.rawValue)")
        _ = await finish(session, stop: stop)
    }

    private func finish(_ session: Session, stop: ProbeReport.Stop) async -> ProbeRun? {
        guard self.session?.directory == session.directory else { return nil }
        self.session = nil
        isCapturing = false
        recorder = nil
        spool = nil
        session.flushTimer.cancel()
        let report = session.recorder.finish(stop)
        // Both `finish` calls wait for pending file writes; keep that off the main actor. An abandoned spool
        // returns its unfinished manifest and writes nothing.
        let (rawDumpURL, spoolManifest) = await Task.detached {
            (session.rawDump?.finish(), session.spool?.finish())
        }.value
        do {
            try store.write(report, to: session.reportURL)
        } catch {
            log.error("report write failed: \(error.localizedDescription)")
        }
        log.notice("capture finished reason=\(stop.reason.rawValue) audioSec=\(report.counters.audioSecondsTotal)"
                   + " spoolSec=\(spoolManifest?.durationSec ?? 0)")
        let run = ProbeRun(directory: session.directory, reportURL: session.reportURL, rawDumpURL: rawDumpURL,
                           report: report, spoolManifest: spoolManifest)
        eventSink.yield(.stopped(run))
        return run
    }

    // MARK: - Configuration

    /// A spool failure must not block the probe: the run continues without spooling and says so in the log.
    private func makeSpool(label: String) -> SegmentedSpoolWriter? {
        guard let spoolDirectory else { return nil }
        do {
            let id = SpoolDirectory.makeSessionID(createdAt: Date())
            let writer = try SegmentedSpoolWriter(
                session: spoolDirectory.makeSession(id: id), label: label.isEmpty ? nil : label)
            log.notice("spool session=\(id)")
            return writer
        } catch {
            log.error("spool unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    private func streamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        if settings.sampleRate > 0 { configuration.sampleRate = settings.sampleRate }
        if settings.channelCount > 0 { configuration.channelCount = settings.channelCount }
        configuration.width = settings.width
        configuration.height = settings.height
        return configuration
    }

    private func reportConfig(styleUsed: String, filter: SCContentFilter) -> ProbeReport.Config {
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let rect = filter.contentRect
        return ProbeReport.Config(
            requestedSampleRate: settings.sampleRate > 0 ? settings.sampleRate : nil,
            requestedChannels: settings.channelCount > 0 ? settings.channelCount : nil,
            width: settings.width, height: settings.height, styleUsed: styleUsed,
            filterStyle: Self.styleName(filter.style),
            filterContentRect: "\(Int(rect.minX)) \(Int(rect.minY)) \(Int(rect.width)) \(Int(rect.height))",
            outputsAdded: settings.addScreenOutput ? ["audio", "screen"] : ["audio"],
            backgroundModes: backgroundModes)
    }

    private static func styleName(_ style: SCShareableContentStyle) -> String {
        switch style {
        case .none: "none"
        case .window: "window"
        case .display: "display"
        @unknown default: "unknown(\(style.rawValue))"
        }
    }

    /// Every 5 s: sample memory and persist the report so a killed app still leaves evidence (G2).
    /// `nonisolated` so the handler is not inferred to be main-actor isolated (it runs on a utility queue).
    private nonisolated static func makeFlushTimer(
        recorder: DiagnosticsRecorder, store: ProbeRunStore, reportURL: URL
    ) -> DispatchSourceTimer {
        let queue = DispatchQueue(label: "\(AppIdentifiers.appBundleID).flush", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler {
            if let reading = MemorySampler.read() { recorder.recordMemory(reading) }
            try? store.write(recorder.snapshot(), to: reportURL)
        }
        return timer
    }
}
#endif
