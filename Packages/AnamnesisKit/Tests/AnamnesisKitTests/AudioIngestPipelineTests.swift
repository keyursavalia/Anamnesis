import CoreMedia
import Foundation
import Testing
@testable import AnamnesisKit

@Suite("AudioIngestPipeline")
struct AudioIngestPipelineTests {
    let recorder = DiagnosticsRecorder(
        runLabel: "R-test", backend: .screenCaptureKit, config: .init(),
        device: DeviceSnapshot.current(), app: BundleSnapshot.current())

    static func sineInt16(amplitude: Float, count: Int) -> [Int16] {
        (0..<count).map { Int16((amplitude * 32_767 * Float(sin(2 * .pi * 440 * Double($0) / 16_000))).rounded()) }
    }

    @Test("measures interleaved Int16 mono and records format, frames and level")
    func int16Mono() throws {
        let pipeline = AudioIngestPipeline(recorder: recorder)
        let amplitude = Float(pow(10, -6.0 / 20))
        pipeline.ingest(try SampleBufferFactory.int16Interleaved(Self.sineInt16(amplitude: amplitude, count: 1_600)),
                        type: .audio)

        let report = recorder.snapshot()
        #expect(report.counters.audioBuffers == 1)
        #expect(report.counters.audioFramesTotal == 1_600)
        #expect(report.firstBuffer?.format.sampleFormat == .int16)
        #expect(report.firstBuffer?.format.sampleRate == 16_000)
        // RMS ≈ -9 dBFS is above -10 dBFS → top histogram bin.
        #expect(report.counters.rmsHistogram[11] == 1)
        #expect(report.counters.silentBuffers == 0)
    }

    @Test("measures non-interleaved Float32 stereo across both channels")
    func float32Planar() throws {
        let pipeline = AudioIngestPipeline(recorder: recorder)
        let silent = [Float](repeating: 0, count: 480)
        let loud = [Float](repeating: 0.5, count: 480)
        pipeline.ingest(try SampleBufferFactory.float32Planar([silent, loud]), type: .audio)
        pipeline.ingest(try SampleBufferFactory.float32Planar([silent, silent], pts: 0.01), type: .audio)

        let report = recorder.snapshot()
        #expect(report.firstBuffer?.format.isInterleaved == false)
        #expect(report.firstBuffer?.format.channels == 2)
        #expect(report.counters.audioBuffers == 2)
        #expect(report.counters.silentBuffers == 1) // only the all-zero buffer
    }

    @Test("video and microphone buffers are counted, not analyzed", arguments: [
        ProbeReport.BufferType.screen, .video, .microphone, .audioMic
    ])
    func countOnly(type: ProbeReport.BufferType) throws {
        let pipeline = AudioIngestPipeline(recorder: recorder)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([1, 2, 3]), type: type)
        let counters = recorder.snapshot().counters
        #expect(counters.byType == [type.rawValue: 1])
        #expect(counters.audioBuffers == 0)
    }

    @Test("ReplayKit app audio is analyzed")
    func replayKitAppAudio() throws {
        let pipeline = AudioIngestPipeline(recorder: recorder)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([100, -100]), type: .audioApp)
        #expect(recorder.snapshot().counters.byType == ["audioApp": 1])
        #expect(recorder.snapshot().counters.audioBuffers == 1)
    }

    @Test("passes presentation timestamps through for gap detection")
    func timestamps() throws {
        let pipeline = AudioIngestPipeline(recorder: recorder)
        let block = [Int16](repeating: 1_000, count: 1_600) // 100 ms at 16 kHz
        for pts in [0.0, 0.1, 0.2, 0.5] {
            pipeline.ingest(try SampleBufferFactory.int16Interleaved(block, pts: pts), type: .audio)
        }
        let gaps = recorder.snapshot().counters.ptsGaps
        #expect(gaps.count == 1)
        #expect(abs(gaps.maxMs - 200) < 0.01)
    }

    @Test("a mid-stream format change is counted")
    func formatChange() throws {
        let pipeline = AudioIngestPipeline(recorder: recorder)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([1, 2]), type: .audio)
        pipeline.ingest(try SampleBufferFactory.float32Planar([[0.1], [0.1]], pts: 1), type: .audio)
        #expect(recorder.snapshot().counters.formatChanges == 1)
    }

    @Test("unsupported sample formats are counted and reported once")
    func unsupportedFormat() throws {
        let pipeline = AudioIngestPipeline(recorder: recorder)
        for index in 0..<3 {
            pipeline.ingest(try SampleBufferFactory.int32Interleaved([1, 2, 3], pts: Double(index)), type: .audio)
        }
        let counters = recorder.snapshot().counters
        #expect(counters.byType == ["audio": 3])
        #expect(counters.audioBuffers == 0)
        #expect(counters.errors.count == 1)
        #expect(counters.errors.first?.domain == AudioIngestPipeline.errorDomain)
    }

    @Test("more channels than the preallocated list are reported, not crashed on")
    func tooManyChannels() throws {
        let pipeline = AudioIngestPipeline(recorder: recorder, maxChannels: 2)
        let channel = [Float](repeating: 0.1, count: 16)
        for _ in 0..<2 {
            pipeline.ingest(try SampleBufferFactory.float32Planar([channel, channel, channel, channel]), type: .audio)
        }
        let counters = recorder.snapshot().counters
        #expect(counters.audioBuffers == 0)
        #expect(counters.byType == ["audio": 2])
        #expect(counters.errors.count == 1)
    }
}
