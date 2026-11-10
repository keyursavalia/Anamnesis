import AVFAudio
import Foundation
import Synchronization

/// Writes captured audio as `seg-NNNNNN.caf` segments of exactly `segmentFrames` (spec 002 R1–R5).
///
/// `enqueue` runs on the capture queue: it copies into the bounded `SpoolInbox` under a short lock and pokes the
/// writer queue through a coalescing dispatch source (no allocation, no waiting). The writer queue converts,
/// quantizes to Int16 (clamping and counting overs, F-009), writes and rotates. `finish` and `abandon` block
/// until the writer is done, so call them off the capture queue.
///
/// `@unchecked Sendable`: the inbox is behind a `Mutex`, `writer` is touched only on `queue`, and `progress`
/// is a `Mutex`. The type is shared between the capture queue, the writer queue and the caller of `finish`.
public final class SegmentedSpoolWriter: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var format: SpoolFormat = .standard
        /// Inbox size in seconds of the largest supported input (48 kHz stereo), ≈ 2 s (spec 002 R3).
        public var inboxSeconds = 2.0
        public var maxInputSampleRate = 48_000.0
        public var maxInputChannels = 2
        /// Descriptor slots: 2 s of SCK's 20-ms buffers is 100; leave headroom for smaller buffers.
        public var maxChunks = 512
        /// PTS jumps beyond this are recorded as gaps; no silence is inserted in v1 (spec 002 §4.2).
        public var ptsGapToleranceSec = 0.02

        public init() {}
    }

    /// Cheap live view for the UI; updated after each drain.
    public struct Progress: Sendable, Equatable {
        public var framesWritten = 0
        public var segmentCount = 0
        public var counters = SpoolCounters()
    }

    public let session: SpoolSession
    private let configuration: Configuration
    private let inbox: Mutex<SpoolInbox>
    private let queue: DispatchQueue
    private let wake: any DispatchSourceUserDataAdd
    private let writer: WriterState
    private let progress = Mutex(Progress())

    /// Writes the initial manifest (`state: active`) so even a session that dies before its first segment is
    /// visible to recovery.
    public init(
        session: SpoolSession, label: String? = nil, createdAt: Date = Date(), configuration: Configuration = .init()
    ) throws {
        self.session = session
        self.configuration = configuration
        let capacity = Int(configuration.inboxSeconds * configuration.maxInputSampleRate)
            * configuration.maxInputChannels
        inbox = Mutex(SpoolInbox(capacitySamples: capacity, maxChunks: configuration.maxChunks))
        let manifest = SpoolManifest(sessionID: session.id, label: label, createdAt: createdAt,
                                     format: configuration.format)
        try manifest.write(to: session.manifestURL)
        writer = WriterState(manifest: manifest, format: configuration.format, maxSamples: capacity)
        queue = DispatchQueue(label: "\(AppIdentifiers.appBundleID).spool", qos: .userInitiated)
        wake = DispatchSource.makeUserDataAddSource(queue: queue)
        wake.setEventHandler { [weak self] in self?.drain() }
        wake.activate()
    }

    deinit {
        wake.cancel()
    }

    /// Capture queue. `list` must stay valid for the call only; it is copied, never retained.
    public func enqueue(_ list: UnsafePointer<AudioBufferList>, format: AudioFormatInfo, frames: Int, pts: Double?) {
        let result = inbox.withLock { $0.push(list, format: format, frames: frames, pts: pts) }
        if result == .accepted { wake.add(data: 1) }
    }

    public func progressSnapshot() -> Progress {
        var snapshot = progress.withLock { $0 }
        inbox.withLock { inbox in Self.merge(inbox, into: &snapshot.counters) }
        return snapshot
    }

    /// Drains the inbox, closes the last segment, finalizes the manifest, then writes `DONE` (spec 002 R5).
    /// Idempotent. Blocks until the writer is idle.
    @discardableResult
    public func finish(at date: Date = Date()) -> SpoolManifest {
        inbox.withLock { $0.isOpen = false }
        return queue.sync {
            guard !writer.isFinished else { return writer.manifest }
            drainOnQueue()
            closeSegment()
            writer.manifest.state = .finished
            writer.manifest.finishedAt = date
            syncInboxCounters()
            do {
                try writer.manifest.write(to: session.manifestURL)
                try Data().write(to: session.doneURL)
            } catch {
                record(.fileFailed("finalize: \(error.localizedDescription)"))
            }
            writer.isFinished = true
            publishProgress()
            return writer.manifest
        }
    }

    /// DEBUG *Simulate crash*: stop without finalizing (no manifest update, no `DONE`), leaving the session for
    /// recovery. The open segment is released without `close()`; AVAudioFile may still finalize its header on
    /// release, which is the best a live process can do to imitate a kill.
    public func abandon() {
        inbox.withLock { $0.isOpen = false }
        queue.sync {
            writer.file = nil
            writer.isFinished = true
        }
    }

    // MARK: - Testing

    func suspendWriterForTesting() { queue.suspend() }
    func resumeWriterForTesting() { queue.resume() }

    // MARK: - Writer queue

    private func drain() {
        drainOnQueue()
        publishProgress()
    }

    private func drainOnQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
        let scratch = writer.scratch
        while let chunk = inbox.withLock({ $0.pop(into: scratch) }) {
            guard !writer.isFinished, !writer.failed else { continue }
            process(chunk)
        }
    }

    private func process(_ chunk: SpoolChunk) {
        let key = SpoolConverter.InputKey(sampleRate: chunk.sampleRate, channels: chunk.channels)
        do throws(SpoolError) {
            if writer.converter.input != key {
                if writer.converter.input != nil { writer.manifest.counters.formatChanges += 1 }
                writer.expectedPTS = nil
                try writer.converter.setInput(key)
            }
            trackGap(chunk)
            try writer.converter.convert(writer.scratch, frames: chunk.frames) { samples throws(SpoolError) in
                try write(samples)
            }
        } catch {
            record(error)
            writer.failed = true
            closeSegment()
        }
    }

    private func trackGap(_ chunk: SpoolChunk) {
        guard let pts = chunk.pts else { return }
        defer { writer.expectedPTS = pts + Double(chunk.frames) / chunk.sampleRate }
        guard let expected = writer.expectedPTS, pts - expected > configuration.ptsGapToleranceSec else { return }
        let gapMs = (pts - expected) * 1_000
        writer.manifest.counters.ptsGaps.count += 1
        writer.manifest.counters.ptsGaps.totalMs += gapMs
        writer.manifest.counters.ptsGaps.maxMs = max(writer.manifest.counters.ptsGaps.maxMs, gapMs)
    }

    /// Splits at the segment boundary so every segment holds exactly `segmentFrames` (except the last).
    private func write(_ samples: UnsafeBufferPointer<Float>) throws(SpoolError) {
        let format = configuration.format
        let frames = samples.count / format.channels
        var offset = 0
        while offset < frames {
            if writer.file == nil { try openSegment() }
            let count = min(format.segmentFrames - writer.framesInSegment, frames - offset,
                            Int(writer.int16Buffer.frameCapacity))
            let piece = UnsafeBufferPointer(rebasing: samples[(offset * format.channels)...]
                .prefix(count * format.channels))
            writer.manifest.counters.clippedSamples += writer.quantize(piece)
            do {
                try writer.file?.write(from: writer.int16Buffer)
            } catch {
                throw .fileFailed("write: \(error.localizedDescription)")
            }
            writer.framesInSegment += count
            writer.framesWritten += count
            offset += count
            if writer.framesInSegment == format.segmentFrames { closeSegment() }
        }
    }

    private func openSegment() throws(SpoolError) {
        let index = writer.manifest.segments.count + 1
        let url = session.segmentURL(index)
        // Safe: `WriterState.init` already built the Int16 buffer from this format.
        let format = configuration.format.pcmFormat.unsafelyUnwrapped
        do {
            writer.file = try AVAudioFile(
                forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            throw .fileFailed("open \(url.lastPathComponent): \(error.localizedDescription)")
        }
        writer.framesInSegment = 0
        writer.manifest.segments.append(SpoolSegmentInfo(
            index: index, fileName: url.lastPathComponent,
            startOffsetSec: configuration.format.seconds(forFrames: writer.framesWritten), frames: 0,
            wallStart: Date(), closedCleanly: false))
        syncInboxCounters()
        // A manifest failure is counted but does not stop audio; recovery rebuilds from the files.
        do { try writer.manifest.write(to: session.manifestURL) } catch {
            record(.fileFailed("manifest: \(error.localizedDescription)"))
        }
    }

    /// Closes and fsyncs the open segment (spec 002 R2); a no-op when none is open.
    private func closeSegment() {
        guard let file = writer.file, let last = writer.manifest.segments.indices.last else { return }
        file.close()
        writer.file = nil
        writer.manifest.segments[last].frames = writer.framesInSegment
        do {
            let handle = try FileHandle(forWritingTo: session.segmentURL(writer.manifest.segments[last].index))
            try handle.synchronize()
            try handle.close()
            writer.manifest.segments[last].closedCleanly = true
        } catch {
            record(.fileFailed("fsync: \(error.localizedDescription)"))
        }
    }

    private func record(_ error: SpoolError) {
        writer.manifest.counters.writeErrors += 1
        if writer.manifest.counters.firstError == nil {
            writer.manifest.counters.firstError = error.localizedDescription
        }
    }

    private func syncInboxCounters() {
        inbox.withLock { inbox in Self.merge(inbox, into: &writer.manifest.counters) }
    }

    private func publishProgress() {
        let snapshot = Progress(
            framesWritten: writer.framesWritten, segmentCount: writer.manifest.segments.count,
            counters: writer.manifest.counters)
        progress.withLock { $0 = snapshot }
    }

    private static func merge(_ inbox: borrowing SpoolInbox, into counters: inout SpoolCounters) {
        counters.dropsQueueFull = inbox.drops
        counters.droppedFrames = inbox.droppedFrames
        counters.invalidBuffers = inbox.invalidBuffers
    }
}

/// Everything the writer queue owns. Not thread-safe by design: touched only on the writer's queue.
private final class WriterState {
    var manifest: SpoolManifest
    let converter: SpoolConverter
    /// Receives one chunk from the inbox; as large as the inbox.
    let scratch: UnsafeMutablePointer<Float>
    let int16Buffer: AVAudioPCMBuffer
    var file: AVAudioFile?
    var framesInSegment = 0
    var framesWritten = 0
    var expectedPTS: Double?
    var failed = false
    var isFinished = false

    init(manifest: SpoolManifest, format: SpoolFormat, maxSamples: Int) {
        self.manifest = manifest
        converter = SpoolConverter(spool: format, maxInputSamples: maxSamples)
        scratch = .allocate(capacity: maxSamples)
        // Safe: SpoolFormat values are positive constants; a 0-Hz or 0-channel format is a programming error.
        let pcmFormat = format.pcmFormat.unsafelyUnwrapped
        // Staging for one `AVAudioFile.write`; `write` splits larger runs into pieces of this size.
        int16Buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 4_096).unsafelyUnwrapped
    }

    deinit {
        scratch.deallocate()
    }

    /// Clamps to [-1, 1] and scales by 32 768 (lossless round trip for Int16 input); returns clamped samples.
    func quantize(_ samples: UnsafeBufferPointer<Float>) -> Int {
        // Safe: Int16 buffers always have `int16ChannelData`; interleaved → one buffer.
        let output = int16Buffer.int16ChannelData.unsafelyUnwrapped[0]
        var clipped = 0
        for (index, sample) in samples.enumerated() {
            if sample > 1 || sample < -1 { clipped += 1 }
            let scaled = (min(max(sample, -1), 1) * 32_768).rounded()
            output[index] = Int16(min(scaled, 32_767))
        }
        int16Buffer.frameLength = AVAudioFrameCount(samples.count / Int(int16Buffer.format.channelCount))
        return clipped
    }
}
