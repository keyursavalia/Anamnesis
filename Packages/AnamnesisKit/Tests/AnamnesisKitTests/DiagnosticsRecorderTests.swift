import CoreAudioTypes
import Foundation
import Synchronization
import Testing
@testable import AnamnesisKit

/// Manually advanced clock so time-dependent fields are deterministic.
final class TestClock: Sendable {
    private let current = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    func now() -> Date { current.withLock { $0 } }
    func advance(by seconds: TimeInterval) { current.withLock { $0 += seconds } }
}

@Suite("DiagnosticsRecorder")
struct DiagnosticsRecorderTests {
    let clock = TestClock()
    static let mono16k = AudioFormatInfo(AudioStreamBasicDescription(
        mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16,
        mReserved: 0))
    static let stereo48k = AudioFormatInfo(AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32,
        mReserved: 0))
    static let loud = LevelMeasurement(peak: 0.5, rms: 0.5)
    static let silent = LevelMeasurement(peak: 0, rms: 0)

    func makeRecorder() -> DiagnosticsRecorder {
        let clock = clock
        return DiagnosticsRecorder(
            runLabel: "R-test", backend: .screenCaptureKit, config: .init(requestedSampleRate: 16_000),
            device: DeviceSnapshot.current(), app: BundleSnapshot.current(), now: { clock.now() })
    }

    /// 1600 frames at 16 kHz = 100 ms per buffer.
    func feed(
        _ recorder: DiagnosticsRecorder, count: Int, startPTS: Double = 0, level: LevelMeasurement = loud,
        format: AudioFormatInfo = mono16k, frames: Int = 1_600
    ) {
        for index in 0..<count {
            let pts = startPTS + Double(index * frames) / format.sampleRate
            recorder.recordAudio(.audio, format: format, frameCount: frames, presentationTimeSec: pts, level: level)
        }
    }

    @Test("counts buffers by type and accumulates audio duration")
    func countsByType() {
        let recorder = makeRecorder()
        recorder.recordBuffer(.screen)
        recorder.recordBuffer(.screen)
        feed(recorder, count: 10)
        let counters = recorder.snapshot().counters
        #expect(counters.byType == ["screen": 2, "audio": 10])
        #expect(counters.audioBuffers == 10)
        #expect(counters.audioFramesTotal == 16_000)
        #expect(abs(counters.audioSecondsTotal - 1) < 1e-9)
    }

    @Test("silent ratio counts buffers below the threshold")
    func silentRatio() {
        let recorder = makeRecorder()
        feed(recorder, count: 3, level: Self.silent)
        feed(recorder, count: 1, startPTS: 0.3)
        let counters = recorder.snapshot().counters
        #expect(counters.silentBuffers == 3)
        #expect(counters.silentRatio == 0.75)
    }

    @Test("contiguous and slightly jittered timestamps produce no gaps")
    func noGaps() {
        let recorder = makeRecorder()
        feed(recorder, count: 5)
        // 2 ms late: within the 5 ms tolerance.
        recorder.recordAudio(
            .audio, format: Self.mono16k, frameCount: 1_600, presentationTimeSec: 0.502, level: Self.loud)
        #expect(recorder.snapshot().counters.ptsGaps == ProbeReport.PTSGaps())
    }

    @Test("a 250 ms hole in timestamps is counted as a gap")
    func detectsGap() {
        let recorder = makeRecorder()
        feed(recorder, count: 5)                 // covers 0.0 ..< 0.5
        feed(recorder, count: 5, startPTS: 0.75) // resumes 250 ms late
        let gaps = recorder.snapshot().counters.ptsGaps
        #expect(gaps.count == 1)
        #expect(abs(gaps.maxMs - 250) < 0.01)
        #expect(abs(gaps.totalMs - 250) < 0.01)
    }

    @Test("format changes are counted and do not register as gaps")
    func formatChanges() {
        let recorder = makeRecorder()
        feed(recorder, count: 2)
        feed(recorder, count: 2, startPTS: 5, format: Self.stereo48k, frames: 480)
        feed(recorder, count: 2, startPTS: 9)
        let counters = recorder.snapshot().counters
        #expect(counters.formatChanges == 2)
        #expect(counters.ptsGaps.count == 0)
    }

    @Test("records the first audio buffer once, with time to first buffer")
    func firstBuffer() throws {
        let recorder = makeRecorder()
        recorder.recordBuffer(.screen)
        clock.advance(by: 1.5)
        feed(recorder, count: 1)
        clock.advance(by: 1)
        feed(recorder, count: 1, startPTS: 9, format: Self.stereo48k, frames: 480)
        let first = try #require(recorder.snapshot().firstBuffer)
        #expect(first.type == .audio)
        #expect(first.format == Self.mono16k)
        #expect(first.framesPerBuffer == 1_600)
        #expect(first.timeToFirstBufferSec == 1.5)
    }

    @Test("histogram bins each buffer by RMS dBFS")
    func histogram() {
        let recorder = makeRecorder()
        feed(recorder, count: 2, level: Self.silent)
        feed(recorder, count: 3, startPTS: 0.2, level: LevelMeasurement(peak: 0.9, rms: 0.5))
        let histogram = recorder.snapshot().counters.rmsHistogram
        #expect(histogram.count == LevelMath.histogramBinCount)
        #expect(histogram[0] == 2)
        #expect(histogram[11] == 3)
        #expect(histogram.reduce(0, +) == 5)
    }

    @Test("timeline has one energy-weighted entry per wall-clock second with audio")
    func timeline() {
        let recorder = makeRecorder()
        feed(recorder, count: 1, level: LevelMeasurement(peak: 1, rms: 1))
        clock.advance(by: 0.5)
        feed(recorder, count: 1, startPTS: 0.1, level: Self.silent)
        clock.advance(by: 1.7) // t = 2.2 s; second 1 delivered nothing
        feed(recorder, count: 1, startPTS: 2.2, level: Self.silent)

        let timeline = recorder.snapshot().timeline
        #expect(timeline.map(\.sec) == [0, 2])
        // mean square of (1, 0) is 0.5 → RMS -3.01 dBFS; second 0 had a non-silent buffer.
        #expect(abs(timeline[0].rmsDb - -3.01) < 0.01)
        #expect(!timeline[0].silent)
        #expect(timeline[1].silent)
        #expect(timeline[1].rmsDb == LevelMath.floorDBFS)
    }

    @Test("markers, errors and memory samples carry seconds since start")
    func markersErrorsMemory() {
        let recorder = makeRecorder()
        clock.advance(by: 2)
        recorder.addMarker(.audibleStart)
        recorder.recordMemory(MemoryReading(physFootprintBytes: 20 * 1_048_576, availableBytes: 40 * 1_048_576))
        clock.advance(by: 3)
        recorder.addMarker(.note, text: "switched reel")
        recorder.recordError(domain: "SCStreamErrorDomain", code: -3821, description: "system stopped")
        recorder.recordMemory(MemoryReading(physFootprintBytes: 28 * 1_048_576, availableBytes: 31 * 1_048_576))
        recorder.recordDroppedBuffer()

        let report = recorder.snapshot()
        #expect(report.markers.map(\.tSec) == [2, 5])
        #expect(report.markers[1].text == "switched reel")
        #expect(report.counters.errors.first?.code == -3821)
        #expect(report.counters.errors.first?.tSec == 5)
        #expect(report.memory.samples.count == 2)
        #expect(report.memory.peakFootprintMB == 28)
        #expect(report.memory.minAvailableMB == 31)
        #expect(report.counters.dropsQueueFull == 1)
    }

    @Test("live level reports the second in progress")
    func liveLevel() {
        let recorder = makeRecorder()
        #expect(recorder.liveLevel() == nil)
        feed(recorder, count: 2, level: LevelMeasurement(peak: 0.5, rms: 0.5))
        let level = recorder.liveLevel()
        #expect(level?.sec == 0)
        #expect(abs((level?.rmsDb ?? 0) - -6.02) < 0.01)
        recorder.finish(ProbeReport.Stop(reason: .user))
        #expect(recorder.liveLevel() == nil)
    }

    @Test("a light snapshot omits the per-second series")
    func lightSnapshot() {
        let recorder = makeRecorder()
        feed(recorder, count: 3)
        recorder.recordMemory(MemoryReading(physFootprintBytes: 1, availableBytes: nil))
        let light = recorder.snapshot(includingSeries: false)
        #expect(light.timeline.isEmpty)
        #expect(light.memory.samples.isEmpty)
        #expect(light.counters.audioBuffers == 3)
    }

    @Test("finish stamps stop info once and ignores later input")
    func finish() {
        let recorder = makeRecorder()
        feed(recorder, count: 2)
        clock.advance(by: 10)
        let report = recorder.finish(ProbeReport.Stop(reason: .error, errorDomain: "d", errorCode: -1))
        clock.advance(by: 5)
        feed(recorder, count: 5, startPTS: 1)
        let again = recorder.finish(ProbeReport.Stop(reason: .user))

        #expect(report.stop?.reason == .error)
        #expect(report.durationSec == 10)
        #expect(report.endedAt == report.startedAt.addingTimeInterval(10))
        #expect(report.thermalStateAtEnd != nil)
        #expect(again == report)
        #expect(recorder.snapshot().counters.audioBuffers == 2)
    }

    @Test("report round-trips through JSON with the current schema version")
    func codable() throws {
        let recorder = makeRecorder()
        feed(recorder, count: 4)
        recorder.addMarker(.audibleEnd)
        let report = recorder.finish(ProbeReport.Stop(reason: .user))
        let decoded = try ProbeReport.decode(from: report.jsonData())
        #expect(decoded == report)
        #expect(decoded.schemaVersion == 1)
        let json = try #require(String(data: report.jsonData(), encoding: .utf8))
        #expect(json.contains("\"backend\" : \"screenCaptureKit\""))
    }

    @Test("concurrent recording and snapshots are consistent")
    func concurrency() async {
        let recorder = makeRecorder()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<500 {
                        recorder.recordAudio(
                            .audio, format: Self.mono16k, frameCount: 160, presentationTimeSec: nil, level: Self.loud)
                    }
                }
            }
            group.addTask {
                for _ in 0..<200 { _ = recorder.snapshot(includingSeries: false) }
            }
        }
        #expect(recorder.snapshot().counters.audioBuffers == 2_000)
    }
}
