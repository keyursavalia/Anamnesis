import AVFAudio
import Foundation

/// Repairs sessions whose writer died before `DONE` (spec 002 R6): validates every segment by reading it,
/// rebuilds offsets and durations from the frames actually readable, discards unreadable files, then writes
/// the manifest and `DONE` so the session is never recovered twice.
public enum SpoolRecovery {
    public struct Result: Sendable, Equatable {
        public var sessionID: String
        /// `.recovered` when at least one segment is usable, otherwise `.interrupted`.
        public var state: SpoolManifest.State
        public var frames: Int
        public var discardedFiles: [String]
        public var manifestWasMissing: Bool
    }

    /// Recovers every unfinished session except those still being written.
    public static func recoverAll(
        in directory: SpoolDirectory, excluding activeIDs: Set<String> = [], at date: Date = Date()
    ) -> [Result] {
        directory.sessions()
            .filter { !activeIDs.contains($0.id) }
            .compactMap { recover($0, at: date) }
    }

    /// nil when the session is already final (`DONE` present).
    public static func recover(_ session: SpoolSession, at date: Date = Date()) -> Result? {
        guard !session.isDone else { return nil }
        let previous = try? SpoolManifest.read(from: session.manifestURL)
        var discarded: [String] = []
        var segments: [SpoolSegmentInfo] = []
        var fileFormat: SpoolFormat?
        var offsetFrames = 0
        for (index, url) in session.segmentFiles() {
            guard let validated = validate(url), validated.frames > 0 else {
                discarded.append(url.lastPathComponent)
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let format = previous?.format ?? validated.format
            fileFormat = fileFormat ?? validated.format
            let old = previous?.segments.first { $0.index == index }
            segments.append(SpoolSegmentInfo(
                index: index, fileName: url.lastPathComponent,
                startOffsetSec: format.seconds(forFrames: offsetFrames), frames: validated.frames,
                wallStart: old?.wallStart ?? previous?.createdAt ?? date,
                closedCleanly: old?.closedCleanly == true && old?.frames == validated.frames))
            offsetFrames += validated.frames
        }
        var manifest = previous ?? SpoolManifest(
            sessionID: session.id, createdAt: segments.first?.wallStart ?? date,
            format: fileFormat ?? .standard)
        manifest.segments = segments
        manifest.state = segments.isEmpty ? .interrupted : .recovered
        manifest.finishedAt = date
        // If this write fails, `DONE` is not written and the next launch tries again.
        do {
            try manifest.write(to: session.manifestURL)
            try Data().write(to: session.doneURL)
        } catch {
            manifest.state = .interrupted
        }
        return Result(sessionID: session.id, state: manifest.state, frames: manifest.totalFrames,
                      discardedFiles: discarded, manifestWasMissing: previous == nil)
    }

    /// Frames that can actually be read (a truncated CAF can claim more than it holds), or nil if unreadable.
    static func validate(_ url: URL) -> (frames: Int, format: SpoolFormat)? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else {
            return nil
        }
        var frames = 0
        while file.framePosition < file.length {
            do {
                try file.read(into: buffer)
            } catch {
                break
            }
            guard buffer.frameLength > 0 else { break }
            frames += Int(buffer.frameLength)
        }
        let format = SpoolFormat(
            sampleRate: file.fileFormat.sampleRate, channels: Int(file.fileFormat.channelCount),
            segmentSeconds: SpoolFormat.standard.segmentSeconds)
        return (frames, format)
    }
}
