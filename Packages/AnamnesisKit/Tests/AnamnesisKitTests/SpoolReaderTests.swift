import AVFAudio
import Foundation
import Testing
@testable import AnamnesisKit

@Suite("SpoolReader")
struct SpoolReaderTests {
    let root = SpoolDirectory(
        root: FileManager.default.temporaryDirectory.appending(path: "SpoolReaderTests-\(UUID().uuidString)"))

    func writeSession(_ source: [Int16]) throws -> SpoolSession {
        var configuration = SegmentedSpoolWriter.Configuration()
        configuration.format = SpoolFormat(sampleRate: 16_000, channels: 1, segmentSeconds: 1)
        let writer = try SegmentedSpoolWriter(session: root.makeSession(id: UUID().uuidString),
                                              configuration: configuration)
        for start in stride(from: 0, to: source.count, by: 320) {
            writer.enqueue(int16: Array(source[start..<min(start + 320, source.count)]))
        }
        writer.finish()
        return writer.session
    }

    func readTimeline(_ reader: SpoolReader, capacity: AVAudioFrameCount) throws -> ([Int16], [Double]) {
        var samples: [Int16] = []
        var offsets: [Double] = []
        try reader.forEachBuffer(frameCapacity: capacity) { buffer, offset in
            offsets.append(offset)
            samples += UnsafeBufferPointer(start: buffer.int16ChannelData?[0], count: Int(buffer.frameLength))
        }
        return (samples, offsets)
    }

    @Test("reads all segments as one continuous timeline with correct offsets")
    func continuous() throws {
        let source = SyntheticPCM.pattern(count: 40_000)
        let reader = try SpoolReader(session: writeSession(source))
        #expect(reader.segments.map(\.info.startOffsetSec) == [0, 1, 2])
        #expect(reader.totalFrames == 40_000)

        let (samples, offsets) = try readTimeline(reader, capacity: 6_000)
        #expect(samples == source)
        // Buffers never cross a segment: 6 000 + 6 000 + 4 000 per full segment.
        #expect(offsets.prefix(4) == [0, 0.375, 0.75, 1])
    }

    @Test("the manifest's frame count wins over a longer file")
    func manifestIsAuthoritative() throws {
        let session = try writeSession(SyntheticPCM.pattern(count: 20_000))
        var manifest = try SpoolManifest.read(from: session.manifestURL)
        manifest.segments[1].frames = 1_000
        try manifest.write(to: session.manifestURL)

        let (samples, _) = try readTimeline(SpoolReader(session: session), capacity: 16_000)
        #expect(samples.count == 17_000)
    }

    @Test("segments missing on disk are skipped")
    func missingFile() throws {
        let session = try writeSession(SyntheticPCM.pattern(count: 20_000))
        try FileManager.default.removeItem(at: session.segmentURL(1))
        let reader = try SpoolReader(session: session)
        #expect(reader.segments.map(\.info.index) == [2])
        #expect(reader.totalFrames == 4_000)
    }

    @Test("pulls a multi-segment session with a gap-free sample clock", arguments: [4_000, 6_000, 16_000])
    func gapFreeClock(capacity: Int) throws {
        let source = SyntheticPCM.pattern(count: 40_000)
        let session = try writeSession(source)
        var cursor = try SpoolReader(session: session).makeCursor()
        var samples: [Int16] = []
        var expectedFrame = 0
        while true {
            // A fresh buffer per pull, as the analyzer input sequence does.
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: cursor.processingFormat,
                                                       frameCapacity: AVAudioFrameCount(capacity)))
            guard let chunk = try cursor.read(into: buffer) else { break }
            #expect(chunk.timelineFrame == expectedFrame)
            #expect(abs(chunk.startOffsetSec - Double(expectedFrame) / 16_000) < 1e-9)
            expectedFrame += Int(buffer.frameLength)
            samples += UnsafeBufferPointer(start: buffer.int16ChannelData?[0], count: Int(buffer.frameLength))
        }
        #expect(samples == source)
        // Reading past the end stays at the end.
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: cursor.processingFormat, frameCapacity: 100))
        #expect(try cursor.read(into: buffer) == nil)
    }
}
