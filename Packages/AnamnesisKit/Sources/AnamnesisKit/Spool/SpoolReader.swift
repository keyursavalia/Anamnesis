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
        for segment in segments {
            let file = try AVAudioFile(forReading: segment.url, commonFormat: .pcmFormatInt16, interleaved: true)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity) else {
                throw SpoolError.fileFailed("buffer for \(segment.info.fileName)")
            }
            var remaining = segment.info.frames
            var position = 0
            while remaining > 0 {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(min(remaining, Int(frameCapacity))))
                let frames = Int(buffer.frameLength)
                guard frames > 0 else { break }
                try body(buffer, segment.info.startOffsetSec + manifest.format.seconds(forFrames: position))
                remaining -= frames
                position += frames
            }
        }
    }
}
