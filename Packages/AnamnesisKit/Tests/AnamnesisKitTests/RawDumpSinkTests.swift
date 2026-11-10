import AVFAudio
import Foundation
import Testing
@testable import AnamnesisKit

@Suite("RawDumpSink")
struct RawDumpSinkTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "RawDumpSinkTests-\(UUID().uuidString)")

    struct ReadBack {
        let frames: AVAudioFramePosition
        let rate: Double
        let firstSamples: [Int16]
    }

    func readBack(_ url: URL) throws -> ReadBack {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4))
        try file.read(into: buffer, frameCount: 4)
        let samples = try #require(buffer.int16ChannelData)
        let first = (0..<Int(buffer.frameLength)).map { samples[0][$0] }
        return ReadBack(frames: file.length, rate: file.fileFormat.sampleRate, firstSamples: first)
    }

    @Test("writes captured PCM to a CAF in the native format")
    func writesPCM() throws {
        let sink = try RawDumpSink(directory: directory)
        sink.append(try SampleBufferFactory.int16Interleaved([10, 20, 30, 40]))
        sink.append(try SampleBufferFactory.int16Interleaved([50, 60], pts: 0.00025))
        let url = try #require(sink.finish())

        #expect(url.pathExtension == "caf")
        let file = try readBack(url)
        #expect(file.frames == 6)
        #expect(file.rate == 16_000)
        #expect(file.firstSamples == [10, 20, 30, 40])
    }

    @Test("stops after the configured duration")
    func capsDuration() throws {
        let sink = try RawDumpSink(directory: directory, maxSeconds: 1)
        let block = [Int16](repeating: 7, count: 1_600) // 100 ms
        for index in 0..<30 {
            sink.append(try SampleBufferFactory.int16Interleaved(block, pts: Double(index) * 0.1))
        }
        let frames = try readBack(try #require(sink.finish())).frames
        #expect(frames >= 16_000)
        #expect(frames < 16_000 + 1_600)
    }

    @Test("stops at a format change instead of writing mixed formats")
    func stopsOnFormatChange() throws {
        let sink = try RawDumpSink(directory: directory)
        sink.append(try SampleBufferFactory.int16Interleaved([1, 2, 3]))
        sink.append(try SampleBufferFactory.float32Planar([[0.5, 0.5]], sampleRate: 48_000, pts: 1))
        sink.append(try SampleBufferFactory.int16Interleaved([4, 5], pts: 2))
        #expect(try readBack(try #require(sink.finish())).frames == 3)
    }

    @Test("finish without audio produces no file")
    func emptyRun() throws {
        let sink = try RawDumpSink(directory: directory)
        #expect(sink.finish() == nil)
    }

    @Test("the pipeline starts the dump at the first non-silent buffer")
    func skipsLeadingSilence() throws {
        let recorder = DiagnosticsRecorder(
            runLabel: "", backend: .screenCaptureKit, config: .init(), device: .current(), app: .current())
        let sink = try RawDumpSink(directory: directory)
        let pipeline = AudioIngestPipeline(recorder: recorder, rawDump: sink)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([0, 0, 0, 0, 0]), type: .audio)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([500, 600], pts: 0.1), type: .audio)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([0, 0, 0], pts: 0.2), type: .audio)
        let file = try readBack(try #require(sink.finish()))
        // Leading silence skipped; silence after speech has started is kept (it is part of the recording).
        #expect(file.frames == 5)
        #expect(file.firstSamples == [500, 600, 0, 0])
    }

    @Test("the pipeline feeds the sink only with analyzed audio")
    func pipelineIntegration() throws {
        let recorder = DiagnosticsRecorder(
            runLabel: "", backend: .replayKit, config: .init(), device: .current(), app: .current())
        let sink = try RawDumpSink(directory: directory)
        let pipeline = AudioIngestPipeline(recorder: recorder, rawDump: sink)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([9, 9]), type: .audioMic)
        pipeline.ingest(try SampleBufferFactory.int16Interleaved([1, 2, 3, 4]), type: .audioApp)
        #expect(try readBack(try #require(sink.finish())).frames == 4)
    }
}
