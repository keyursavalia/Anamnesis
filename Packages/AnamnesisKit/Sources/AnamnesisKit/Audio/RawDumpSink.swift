import AVFAudio
import CoreMedia
import Foundation
import Synchronization

/// SPIKE: writes the first `maxSeconds` of captured audio (from the first non-silent buffer, see the pipeline)
/// to `raw.caf` in its native format so the operator can
/// confirm by ear that the capture is real speech at the right speed (spec 001 §4.6). Off by default.
///
/// `append` runs on the capture queue: it copies the PCM (one allocation per buffer — tolerated because this is
/// opt-in and bounded to `maxSeconds`) and hands the copy to a private serial queue for the file write, so no
/// disk I/O happens on the capture thread. The `CMSampleBuffer` itself is never retained.
public final class RawDumpSink: Sendable {
    public static let defaultMaxSeconds = 20.0

    public let fileURL: URL
    private let maxSeconds: Double
    private let writerQueue = DispatchQueue(label: "\(AppIdentifiers.appBundleID).rawdump", qos: .utility)
    /// Capture-queue side: whether we are still accepting audio and how much has been accepted.
    private let intake = Mutex(Intake())
    /// Writer-queue side; only touched on `writerQueue`.
    private let writer = Mutex(Writer())

    private struct Intake {
        var format: AVAudioFormat?
        /// Counted in frames, not seconds, so the cap is exact (summing 0.1 s steps drifts below the limit).
        var acceptedFrames = 0
        var isClosed = false
    }

    private struct Writer {
        var file: AVAudioFile?
        var failed = false
    }

    /// Wraps a copied PCM buffer for the hop to the writer queue. `AVAudioPCMBuffer` is not Sendable, but the
    /// copy is created on the capture queue and touched only by the writer afterwards (single owner).
    private struct PendingBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    public init(directory: URL, maxSeconds: Double = RawDumpSink.defaultMaxSeconds) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "raw.caf")
        self.maxSeconds = maxSeconds
    }

    /// Copies `sampleBuffer` for writing if the dump is still open. Stops for good at `maxSeconds` or a format change.
    public func append(_ sampleBuffer: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        let accepted: AVAudioFormat? = intake.withLock { intake in
            guard !intake.isClosed, frames > 0 else { return nil }
            if let format = intake.format, !Self.sameFormat(format.streamDescription.pointee, asbd.pointee) {
                intake.isClosed = true // a CAF holds one format; keep what we have
                return nil
            }
            if intake.format == nil {
                guard let format = AVAudioFormat(streamDescription: asbd) else {
                    intake.isClosed = true
                    return nil
                }
                intake.format = format
            }
            intake.acceptedFrames += frames
            if Double(intake.acceptedFrames) >= maxSeconds * asbd.pointee.mSampleRate { intake.isClosed = true }
            return intake.format
        }
        guard let format = accepted, let copy = Self.copyPCM(sampleBuffer, format: format, frames: frames) else {
            return
        }
        let pending = PendingBuffer(buffer: copy)
        writerQueue.async { [self] in write(pending.buffer) }
    }

    /// Flushes pending writes and closes the file; call it off the capture queue.
    /// Returns the file if anything was written.
    @discardableResult
    public func finish() -> URL? {
        intake.withLock { $0.isClosed = true }
        return writerQueue.sync {
            writer.withLock { writer in
                let wroteAudio = writer.file != nil && !writer.failed
                writer.file = nil // AVAudioFile closes on release
                return wroteAudio ? fileURL : nil
            }
        }
    }

    // MARK: - Private

    private func write(_ buffer: AVAudioPCMBuffer) {
        writer.withLock { writer in
            guard !writer.failed else { return }
            do {
                if writer.file == nil {
                    let format = buffer.format
                    writer.file = try AVAudioFile(
                        forWriting: fileURL, settings: format.settings, commonFormat: format.commonFormat,
                        interleaved: format.isInterleaved)
                }
                try writer.file?.write(from: buffer)
            } catch {
                writer.failed = true
                writer.file = nil
            }
        }
    }

    private static func copyPCM(
        _ sampleBuffer: CMSampleBuffer, format: AVAudioFormat, frames: Int
    ) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            return nil
        }
        copy.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: copy.mutableAudioBufferList)
        return status == noErr ? copy : nil
    }

    private static func sameFormat(_ lhs: AudioStreamBasicDescription, _ rhs: AudioStreamBasicDescription) -> Bool {
        lhs.mSampleRate == rhs.mSampleRate && lhs.mFormatID == rhs.mFormatID && lhs.mFormatFlags == rhs.mFormatFlags
            && lhs.mChannelsPerFrame == rhs.mChannelsPerFrame && lhs.mBitsPerChannel == rhs.mBitsPerChannel
    }
}
