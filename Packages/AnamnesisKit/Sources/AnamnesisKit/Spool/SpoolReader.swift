import AVFAudio
import Foundation

/// Reads a finished (or recovered) session as one continuous timeline (spec 002 R8), one bounded buffer at a
/// time, never a whole file. The manifest's frame counts are authoritative: a recovered segment may be shorter
/// than its CAF header claims.
public struct SpoolReader: Sendable {
    public struct Segment: Sendable, Equatable {
        public var info: SpoolSegmentInfo
        public var url: URL
    }

    public let manifest: SpoolManifest
    /// Segments in order whose files exist; offsets are the manifest's cumulative written seconds.
    public let segments: [Segment]

    public init(session: SpoolSession) throws {
        manifest = try SpoolManifest.read(from: session.manifestURL)
        segments = manifest.segments
            .sorted { $0.index < $1.index }
            .filter { $0.frames > 0 }
            .map { Segment(info: $0, url: session.directory.appending(path: $0.fileName)) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) }
    }

    public var totalFrames: Int { segments.reduce(0) { $0 + $1.info.frames } }

    /// Calls `body` with consecutive buffers (≤ `frameCapacity` frames, spool format) and the timeline offset in
    /// seconds of each buffer's first frame. The buffer is reused between calls; copy what you keep.
    public func forEachBuffer(
        frameCapacity: AVAudioFrameCount = 16_000,
        _ body: (AVAudioPCMBuffer, _ startOffsetSec: Double) throws -> Void
    ) throws {
        var cursor = makeCursor()
        guard let buffer = AVAudioPCMBuffer(pcmFormat: cursor.processingFormat, frameCapacity: frameCapacity) else {
            throw SpoolError.fileFailed("buffer for session \(manifest.sessionID)")
        }
        while let chunk = try cursor.read(into: buffer) {
            try body(buffer, chunk.startOffsetSec)
        }
    }

    public func makeCursor() -> Cursor { Cursor(reader: self) }

    /// Where one buffer read by a `Cursor` sits on the session timeline.
    public struct Chunk: Sendable, Equatable {
        /// The manifest's offset of the buffer's first frame (spec 002 timeline).
        public var startOffsetSec: Double
        /// Frames delivered before this buffer: a gap-free sample clock for `bufferStartTime`.
        public var timelineFrame: Int
    }

    /// Pull-based reading for consumers that ask for one buffer at a time (spec 003 R4: the analyzer's input
    /// sequence). Holds at most one open segment file. Not Sendable: keep it on one task.
    public struct Cursor {
        private let reader: SpoolReader
        private var segmentIndex = 0
        private var file: AVAudioFile?
        private var remaining = 0
        private var position = 0
        private var delivered = 0

        init(reader: SpoolReader) {
            self.reader = reader
        }

        /// Spool format as `AVAudioFile` reads it (Int16 interleaved); size buffers for `read(into:)` with it.
        public var processingFormat: AVAudioFormat {
            // Safe: SpoolFormat is always 16-bit PCM with 1–2 channels, which AVAudioFormat accepts.
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: reader.manifest.format.sampleRate,
                          channels: AVAudioChannelCount(reader.manifest.format.channels), interleaved: true)!
        }

        /// Fills `buffer` with the next frames (never crossing a segment); nil at the end of the timeline.
        public mutating func read(into buffer: AVAudioPCMBuffer) throws -> Chunk? {
            while segmentIndex < reader.segments.count {
                let segment = reader.segments[segmentIndex]
                if file == nil {
                    file = try AVAudioFile(forReading: segment.url, commonFormat: .pcmFormatInt16, interleaved: true)
                    remaining = segment.info.frames
                    position = 0
                }
                if remaining > 0, let file {
                    let count = AVAudioFrameCount(min(remaining, Int(buffer.frameCapacity)))
                    try file.read(into: buffer, frameCount: count)
                    let frames = Int(buffer.frameLength)
                    if frames > 0 {
                        let offset = segment.info.startOffsetSec + reader.manifest.format.seconds(forFrames: position)
                        let chunk = Chunk(startOffsetSec: offset, timelineFrame: delivered)
                        remaining -= frames
                        position += frames
                        delivered += frames
                        return chunk
                    }
                }
                file = nil
                segmentIndex += 1
            }
            return nil
        }
    }
}
