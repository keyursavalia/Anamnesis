import AudioToolbox
import CoreAudio

/// One captured buffer waiting in the inbox: interleaved Float32 at its native rate and channel count.
struct SpoolChunk: Equatable {
    var sampleRate: Double
    var channels: Int
    var frames: Int
    var pts: Double?

    var sampleCount: Int { frames * channels }
}

/// Bounded hand-off from the capture queue to the writer queue (spec 002 R3, CONVENTIONS §2).
///
/// A fixed ring of Float32 samples plus a fixed ring of chunk descriptors, both allocated once. `push` converts
/// Int16/Float32, interleaved/planar input into interleaved Float32 straight into the ring, so the capture
/// thread never allocates, never waits for the writer and never touches the disk. When either ring is full the
/// newest buffer is dropped and counted. Guarded by the writer's `Mutex`; holds no lock itself.
///
/// `@unchecked Sendable`: the ring storage is owned by this value and only reached through the `Mutex`;
/// the pointers passed to `push`/`pop` are read or written during the call and never stored.
struct SpoolInbox: ~Copyable, @unchecked Sendable {
    enum PushResult: Equatable {
        case accepted
        /// No room: dropped and counted.
        case full
        /// Unsupported sample format or a buffer list that does not match the format; counted.
        case invalid
    }

    let capacity: Int
    private let samples: UnsafeMutablePointer<Float>
    private var start = 0
    private var count = 0
    private var chunks: [SpoolChunk]
    private var chunkStart = 0
    private var chunkCount = 0

    /// Closed by `finish`/`abandon`; later pushes are ignored.
    var isOpen = true
    private(set) var drops = 0
    private(set) var droppedFrames = 0
    private(set) var invalidBuffers = 0

    init(capacitySamples: Int, maxChunks: Int) {
        capacity = max(1, capacitySamples)
        samples = .allocate(capacity: capacity)
        chunks = Array(repeating: SpoolChunk(sampleRate: 0, channels: 0, frames: 0), count: max(1, maxChunks))
    }

    deinit {
        samples.deallocate()
    }

    var isEmpty: Bool { chunkCount == 0 }

    mutating func push(
        _ list: UnsafePointer<AudioBufferList>, format: AudioFormatInfo, frames: Int, pts: Double?
    ) -> PushResult {
        guard isOpen else { return .full }
        let channels = Int(format.channels)
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard frames > 0, channels > 0, let bytesPerSample = Self.bytesPerSample(format.sampleFormat),
              Self.holds(buffers, frames: frames, channels: channels, bytesPerSample: bytesPerSample,
                         interleaved: format.isInterleaved) else {
            invalidBuffers += 1
            return .invalid
        }
        let needed = frames * channels
        guard needed <= capacity - count, chunkCount < chunks.count else {
            drops += 1
            droppedFrames += frames
            return .full
        }
        copy(buffers, format: format, frames: frames, channels: channels)
        chunks[(chunkStart + chunkCount) % chunks.count] = SpoolChunk(
            sampleRate: format.sampleRate, channels: channels, frames: frames, pts: pts)
        chunkCount += 1
        count += needed
        return .accepted
    }

    /// Moves the oldest chunk's samples into `destination` (capacity ≥ `capacity`); nil when empty.
    mutating func pop(into destination: UnsafeMutablePointer<Float>) -> SpoolChunk? {
        guard chunkCount > 0 else { return nil }
        let chunk = chunks[chunkStart]
        let total = chunk.sampleCount
        let firstPart = min(total, capacity - start)
        destination.update(from: samples + start, count: firstPart)
        if firstPart < total { (destination + firstPart).update(from: samples, count: total - firstPart) }
        start = (start + total) % capacity
        count -= total
        chunkStart = (chunkStart + 1) % chunks.count
        chunkCount -= 1
        return chunk
    }

    // MARK: - Private

    private func copy(
        _ buffers: UnsafeMutableAudioBufferListPointer, format: AudioFormatInfo, frames: Int, channels: Int
    ) {
        var index = (start + count) % capacity
        let isInt16 = format.sampleFormat == .int16
        for frame in 0..<frames {
            for channel in 0..<channels {
                // Safe: `holds` checked every buffer has data for `frames` × its channels.
                let (buffer, offset) = format.isInterleaved
                    ? (buffers[0], frame * channels + channel)
                    : (buffers[channel], frame)
                let data = buffer.mData.unsafelyUnwrapped
                samples[index] = isInt16
                    ? Float(data.assumingMemoryBound(to: Int16.self)[offset]) / 32_768
                    : data.assumingMemoryBound(to: Float.self)[offset]
                index += 1
                if index == capacity { index = 0 }
            }
        }
    }

    private static func bytesPerSample(_ format: AudioFormatInfo.SampleFormat) -> Int? {
        switch format {
        case .int16: MemoryLayout<Int16>.size
        case .float32: MemoryLayout<Float>.size
        case .unsupported: nil
        }
    }

    private static func holds(
        _ buffers: UnsafeMutableAudioBufferListPointer, frames: Int, channels: Int, bytesPerSample: Int,
        interleaved: Bool
    ) -> Bool {
        let needed = interleaved ? 1 : channels
        guard buffers.count >= needed else { return false }
        let bytes = frames * bytesPerSample * (interleaved ? channels : 1)
        return buffers.prefix(needed).allSatisfy { $0.mData != nil && Int($0.mDataByteSize) >= bytes }
    }
}
