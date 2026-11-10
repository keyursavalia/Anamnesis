import AVFAudio
import Foundation
import Testing
@testable import AnamnesisKit

@Suite("SegmentedSpoolWriter")
struct SegmentedSpoolWriterTests {
    let root = SpoolDirectory(
        root: FileManager.default.temporaryDirectory.appending(path: "SpoolWriterTests-\(UUID().uuidString)"))

    /// 1-s segments keep the files small; the rotation logic is the same as for 60 s.
    func makeWriter(
        segmentSeconds: Int = 1, configure: (inout SegmentedSpoolWriter.Configuration) -> Void = { _ in }
    ) throws -> SegmentedSpoolWriter {
        var configuration = SegmentedSpoolWriter.Configuration()
        configuration.format = SpoolFormat(sampleRate: 16_000, channels: 1, segmentSeconds: segmentSeconds)
        configure(&configuration)
        return try SegmentedSpoolWriter(session: root.makeSession(id: UUID().uuidString), configuration: configuration)
    }

    func feed(_ writer: SegmentedSpoolWriter, _ samples: [Int16], chunk: Int = 320) {
        for start in stride(from: 0, to: samples.count, by: chunk) {
            let end = min(start + chunk, samples.count)
            writer.enqueue(int16: Array(samples[start..<end]), pts: Double(start) / 16_000)
        }
    }

    @Test("rotates exactly at segmentFrames and finalizes every segment")
    func rotation() throws {
        let writer = try makeWriter()
        feed(writer, SyntheticPCM.pattern(count: 56_000)) // 3.5 s
        let manifest = writer.finish()

        #expect(manifest.segments.map(\.frames) == [16_000, 16_000, 16_000, 8_000])
        #expect(manifest.segments.map(\.startOffsetSec) == [0, 1, 2, 3])
        #expect(manifest.segments.allSatisfy { $0.closedCleanly })
        #expect(manifest.state == .finished)
        #expect(manifest.durationSec == 3.5)
        #expect(writer.session.isDone)
        // Dates are stored at whole-second precision, so compare the content that matters.
        let stored = try SpoolManifest.read(from: writer.session.manifestURL)
        #expect(stored.segments.map(\.frames) == manifest.segments.map(\.frames))
        #expect(stored.state == .finished && stored.counters == manifest.counters)
        for (info, (_, url)) in zip(manifest.segments, writer.session.segmentFiles()) {
            #expect(try AVAudioFile(forReading: url).length == AVAudioFramePosition(info.frames))
        }
    }

    @Test("splitting buffers across boundaries loses and duplicates nothing", arguments: [1, 7, 320, 1_499, 4_097])
    func lossless(chunk: Int) throws {
        // Room for 40 k one-frame buffers: this test is about boundaries, not overflow.
        let writer = try makeWriter { $0.maxChunks = 50_000 }
        let source = SyntheticPCM.pattern(count: 40_123, seed: chunk)
        feed(writer, source, chunk: chunk)
        #expect(writer.finish().counters.dropsQueueFull == 0)
        #expect(try SyntheticPCM.readAll(writer.session) == source)
    }

    @Test("Float32 above full scale is clamped and counted (F-009)")
    func clamps() throws {
        let writer = try makeWriter()
        writer.enqueue(float32: [1.5, -2, 0.5, 1, -1, 0])
        let manifest = writer.finish()
        #expect(try SyntheticPCM.readAll(writer.session) == [32_767, -32_768, 16_384, 32_767, -32_768, 0])
        #expect(manifest.counters.clippedSamples == 2)
    }

    @Test("a mid-stream format change rebuilds the converter and keeps writing")
    func formatChange() throws {
        let writer = try makeWriter(segmentSeconds: 60)
        feed(writer, SyntheticPCM.pattern(count: 8_000))
        let stereo = SyntheticPCM.sine(frames: 24_000, sampleRate: 48_000) // 0.5 s at 48 kHz
        for start in stride(from: 0, to: stereo.count, by: 960) {
            let slice = Array(stereo[start..<start + 960])
            writer.enqueue(planar: [slice, slice], sampleRate: 48_000)
        }
        feed(writer, SyntheticPCM.pattern(count: 8_000))
        let manifest = writer.finish()

        #expect(manifest.counters.formatChanges == 2)
        #expect(manifest.counters.writeErrors == 0)
        // 0.5 s + ~0.5 s resampled (minus resampler latency) + 0.5 s.
        #expect(abs(manifest.totalFrames - 24_000) < 200)
    }

    @Test("a full inbox drops and counts without blocking the producer")
    func overflow() throws {
        // 0.01 s × 48 kHz × 2 ch = 960 samples = three 320-frame mono buffers.
        let writer = try makeWriter { $0.inboxSeconds = 0.01 }
        writer.suspendWriterForTesting()
        var slowest = Duration.zero
        let clock = ContinuousClock()
        for index in 0..<100 {
            let elapsed = clock.measure {
                writer.enqueue(int16: [Int16](repeating: 1, count: 320), pts: Double(index) * 0.02)
            }
            slowest = max(slowest, elapsed)
        }
        writer.resumeWriterForTesting()
        let manifest = writer.finish()

        #expect(manifest.counters.dropsQueueFull == 97)
        #expect(manifest.counters.droppedFrames == 97 * 320)
        #expect(manifest.totalFrames == 960)
        #expect(slowest < .milliseconds(5))
    }

    @Test("records PTS gaps beyond the tolerance")
    func gaps() throws {
        let writer = try makeWriter()
        let block = [Int16](repeating: 5, count: 320) // 20 ms
        for pts in [0, 0.02, 0.04, 0.12, 0.14] { writer.enqueue(int16: block, pts: pts) }
        let gaps = writer.finish().counters.ptsGaps
        #expect(gaps.count == 1)
        #expect(abs(gaps.maxMs - 60) < 0.01)
    }

    @Test("DONE is written only by finish; finish is idempotent and closes the inbox")
    func finishSemantics() throws {
        let writer = try makeWriter()
        #expect(try SpoolManifest.read(from: writer.session.manifestURL).state == .active)
        feed(writer, SyntheticPCM.pattern(count: 3_200))
        #expect(!writer.session.isDone)

        let first = writer.finish()
        writer.enqueue(int16: SyntheticPCM.pattern(count: 320))
        let second = writer.finish()
        #expect(first == second)
        #expect(second.totalFrames == 3_200)
        #expect(writer.session.isDone)
    }

    @Test("abandon leaves an unfinished session for recovery")
    func abandon() throws {
        let writer = try makeWriter()
        feed(writer, SyntheticPCM.pattern(count: 20_000))
        _ = writer.progressSnapshot()
        writer.abandon()
        #expect(!writer.session.isDone)
        #expect(try SpoolManifest.read(from: writer.session.manifestURL).state == .active)
    }

    @Test("unsupported layouts are counted, not written")
    func invalidInput() throws {
        let writer = try makeWriter()
        let format = AnamnesisKit.AudioFormatInfo(SampleBufferFactory.makeASBD(
            sampleRate: 16_000, channels: 1, bits: 32, flags: kAudioFormatFlagIsSignedInteger, interleaved: true))
        var samples: [Int32] = [1, 2, 3]
        samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            writer.enqueue(&list, format: format, frames: 3, pts: nil)
        }
        let manifest = writer.finish()
        #expect(manifest.counters.invalidBuffers == 1)
        #expect(manifest.segments.isEmpty)
    }

    @Test("progress reflects written frames and segments")
    func progress() throws {
        let writer = try makeWriter()
        feed(writer, SyntheticPCM.pattern(count: 20_000))
        writer.finish()
        let progress = writer.progressSnapshot()
        #expect(progress.framesWritten == 20_000)
        #expect(progress.segmentCount == 2)
    }

    @Test("the ingest pipeline spools every analyzed audio buffer, silent or not")
    func pipeline() throws {
        let writer = try makeWriter()
        let recorder = DiagnosticsRecorder(
            runLabel: "", backend: .screenCaptureKit, config: .init(), device: .current(), app: .current())
        let pipeline = AudioIngestPipeline(recorder: recorder, spool: writer)
        let silence = [Float](repeating: 0, count: 320)
        let tone = SyntheticPCM.sine(frames: 320, sampleRate: 16_000)
        pipeline.ingest(try SampleBufferFactory.float32Planar([silence], sampleRate: 16_000), type: .audio)
        pipeline.ingest(try SampleBufferFactory.float32Planar([tone], sampleRate: 16_000, pts: 0.02), type: .audio)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([1, 2, 3], pts: 0.04), type: .screen)
        let manifest = writer.finish()
        #expect(manifest.totalFrames == 640)
        #expect(manifest.counters.formatChanges == 0)
        let samples = try SyntheticPCM.readAll(writer.session)
        #expect(samples.prefix(320).allSatisfy { $0 == 0 })
        #expect(samples[320 + 5] == Int16((tone[5] * 32_768).rounded()))
    }
}
