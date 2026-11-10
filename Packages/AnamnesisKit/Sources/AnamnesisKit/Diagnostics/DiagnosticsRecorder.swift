import Foundation
import Synchronization

/// Accumulates counters for one probe run and produces a `ProbeReport` (spec 001 §4.3).
///
/// Called from the capture callback queue: every `record…` method takes a short lock, does O(1) work
/// and never logs or touches disk. Per-second series grow by at most one element per second.
/// `snapshot` may be called from any thread (Lab UI polls it at ~2 Hz).
public final class DiagnosticsRecorder: Sendable {
    public struct Settings: Sendable {
        /// Peak below this (linear full scale) counts as a silent buffer.
        public var silenceThreshold: Float = LevelMath.defaultSilenceThreshold
        /// PTS further than this past the expected next timestamp counts as a gap.
        public var ptsGapToleranceSec = 0.005
        /// Timeline stops growing after this many seconds (4 h) to bound memory.
        public var maxTimelineSeconds = 4 * 3_600

        public init() {}
    }

    private struct SecondAccumulator {
        var sec: Int
        var weightedSquares = 0.0
        var frames = 0
        var allSilent = true

        var entry: ProbeReport.TimelineSecond {
            let meanSquare = frames > 0 ? weightedSquares / Double(frames) : 0
            return .init(sec: sec, rmsDb: LevelMath.dbfs(Float(meanSquare.squareRoot())), silent: allSilent)
        }
    }

    private struct State {
        var report: ProbeReport
        var lastFormat: AudioFormatInfo?
        var expectedNextPTS: Double?
        var currentSecond: SecondAccumulator?
        var isFinished = false
    }

    private let settings: Settings
    private let now: @Sendable () -> Date
    private let startedAt: Date
    private let state: Mutex<State>

    public init(
        runLabel: String,
        backend: ProbeReport.Backend,
        config: ProbeReport.Config,
        device: DeviceSnapshot,
        app: BundleSnapshot,
        notes: String = "",
        settings: Settings = Settings(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.now = now
        startedAt = now()
        let report = ProbeReport(
            runLabel: runLabel, backend: backend, startedAt: startedAt, endedAt: nil, durationSec: 0,
            device: device, thermalStateAtEnd: nil, app: app, config: config, notes: notes)
        state = Mutex(State(report: report))
    }

    // MARK: - Recording (capture queue)

    /// Counts a buffer that is not analyzed (video frames, microphone).
    public func recordBuffer(_ type: ProbeReport.BufferType) {
        state.withLock { state in
            guard !state.isFinished else { return }
            state.report.counters.byType[type.rawValue, default: 0] += 1
        }
    }

    /// Records one analyzed audio buffer. `presentationTimeSec` is the buffer's PTS, if valid.
    public func recordAudio(
        _ type: ProbeReport.BufferType,
        format: AudioFormatInfo,
        frameCount: Int,
        presentationTimeSec: Double?,
        level: LevelMeasurement
    ) {
        let tSec = elapsed()
        state.withLock { state in
            guard !state.isFinished else { return }
            let isSilent = level.isSilent(threshold: settings.silenceThreshold)
            let seconds = format.sampleRate > 0 ? Double(frameCount) / format.sampleRate : 0
            state.report.counters.addAudio(
                type, frameCount: frameCount, seconds: seconds, level: level, silent: isSilent)
            if state.report.firstBuffer == nil {
                state.report.firstBuffer = .init(
                    type: type, format: format, framesPerBuffer: frameCount, timeToFirstBufferSec: tSec)
            }
            trackFormatAndGaps(&state, format: format, frameCount: frameCount, pts: presentationTimeSec, tSec: tSec)
            addToTimeline(&state, tSec: tSec, frameCount: frameCount, level: level, silent: isSilent)
        }
    }

    /// The bounded hand-off queue was full and a buffer was discarded.
    public func recordDroppedBuffer() {
        state.withLock { state in
            guard !state.isFinished else { return }
            state.report.counters.dropsQueueFull += 1
        }
    }

    public func recordError(domain: String, code: Int, description: String) {
        let tSec = elapsed()
        state.withLock { state in
            state.report.counters.errors.append(.init(tSec: tSec, domain: domain, code: code, description: description))
        }
    }

    // MARK: - Recording (any thread, low rate)

    public func addMarker(_ kind: ProbeReport.MarkerKind, text: String? = nil) {
        let tSec = elapsed()
        state.withLock { state in
            guard !state.isFinished else { return }
            state.report.markers.append(.init(tSec: tSec, kind: kind, text: text))
        }
    }

    public func recordMemory(_ reading: MemoryReading) {
        let tSec = elapsed()
        state.withLock { state in
            guard !state.isFinished else { return }
            var memory = state.report.memory
            memory.samples.append(.init(tSec: tSec, physFootprintMB: reading.physFootprintMB,
                                        osAvailableMB: reading.availableMB))
            memory.peakFootprintMB = max(memory.peakFootprintMB, reading.physFootprintMB)
            if let available = reading.availableMB {
                memory.minAvailableMB = min(memory.minAvailableMB ?? available, available)
            }
            state.report.memory = memory
        }
    }

    public func setNotes(_ notes: String) {
        state.withLock { $0.report.notes = notes }
    }

    // MARK: - Output

    /// The report so far. `includingSeries: false` skips the per-second arrays (cheap enough for 2 Hz UI polling).
    public func snapshot(includingSeries: Bool = true) -> ProbeReport {
        let end = now()
        return state.withLock { state in
            var report = state.report
            if includingSeries {
                // Copy eagerly: sharing storage would make the capture thread's next append pay for the copy.
                report.timeline = state.report.timeline.map { $0 }
                report.memory.samples = state.report.memory.samples.map { $0 }
            } else {
                report.timeline = []
                report.memory.samples = []
            }
            if !state.isFinished {
                report.durationSec = end.timeIntervalSince(report.startedAt)
                if includingSeries, let second = state.currentSecond { report.timeline.append(second.entry) }
            }
            return report
        }
    }

    /// Level of the wall-clock second in progress, for a live meter; nil if no audio arrived this second.
    public func liveLevel() -> ProbeReport.TimelineSecond? {
        state.withLock { $0.currentSecond?.entry }
    }

    /// Stamps the stop reason and freezes the report. Later calls return the same report and later input is ignored.
    @discardableResult
    public func finish(
        _ stop: ProbeReport.Stop, thermalStateAtEnd: String = DeviceSnapshot.currentThermalStateName()
    ) -> ProbeReport {
        let end = now()
        return state.withLock { state in
            guard !state.isFinished else { return state.report }
            state.isFinished = true
            if let second = state.currentSecond { state.report.timeline.append(second.entry) }
            state.currentSecond = nil
            state.report.endedAt = end
            state.report.durationSec = end.timeIntervalSince(state.report.startedAt)
            state.report.thermalStateAtEnd = thermalStateAtEnd
            state.report.stop = stop
            return state.report
        }
    }

    // MARK: - Private

    private func elapsed() -> Double {
        now().timeIntervalSince(startedAt)
    }

    private func trackFormatAndGaps(
        _ state: inout State, format: AudioFormatInfo, frameCount: Int, pts: Double?, tSec: Double
    ) {
        if let last = state.lastFormat, last != format {
            state.report.counters.formatChanges += 1
            // A new format restarts the timestamp sequence; don't report the switch as a gap.
            state.expectedNextPTS = nil
        }
        state.lastFormat = format
        if let pts, let expected = state.expectedNextPTS {
            let gap = pts - expected
            if gap > settings.ptsGapToleranceSec {
                state.report.counters.ptsGaps.count += 1
                state.report.counters.ptsGaps.maxMs = max(state.report.counters.ptsGaps.maxMs, gap * 1_000)
                state.report.counters.ptsGaps.totalMs += gap * 1_000
                // Bounded, and rare (a gap is an anomaly), so the occasional append is acceptable here.
                var events = state.report.counters.ptsGaps.events ?? []
                if events.count < ProbeReport.PTSGaps.maxEvents {
                    events.append(.init(tSec: tSec, durationMs: gap * 1_000))
                    state.report.counters.ptsGaps.events = events
                }
            }
        }
        state.expectedNextPTS = pts.flatMap { pts in
            format.sampleRate > 0 ? pts + Double(frameCount) / format.sampleRate : nil
        }
    }

    private func addToTimeline(
        _ state: inout State, tSec: Double, frameCount: Int, level: LevelMeasurement, silent: Bool
    ) {
        let sec = Int(tSec.rounded(.down))
        guard sec < settings.maxTimelineSeconds else { return }
        if let current = state.currentSecond, current.sec != sec {
            state.report.timeline.append(current.entry)
            state.currentSecond = nil
        }
        var second = state.currentSecond ?? SecondAccumulator(sec: sec)
        second.weightedSquares += Double(level.rms) * Double(level.rms) * Double(frameCount)
        second.frames += frameCount
        second.allSilent = second.allSilent && silent
        state.currentSecond = second
    }
}

private extension ProbeReport.Counters {
    mutating func addAudio(
        _ type: ProbeReport.BufferType, frameCount: Int, seconds: Double, level: LevelMeasurement, silent: Bool
    ) {
        byType[type.rawValue, default: 0] += 1
        audioBuffers += 1
        audioFramesTotal += frameCount
        audioSecondsTotal += seconds
        if silent { silentBuffers += 1 }
        silentRatio = Double(silentBuffers) / Double(audioBuffers)
        rmsHistogram[LevelMath.histogramBin(forDBFS: level.rmsDBFS)] += 1
    }
}
