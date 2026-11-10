import AudioToolbox
import CoreMedia
import Foundation

/// Per-buffer analysis shared by both capture backends (spec 001 §4.5):
/// format detection → PTS → zero-copy PCM access → peak/RMS → `DiagnosticsRecorder`.
///
/// Real-time rules (CONVENTIONS §3): no allocation in the steady state (the buffer list is preallocated and the
/// last format is cached), no logging, no disk I/O, and the `CMSampleBuffer` is not retained past `ingest`.
/// Not thread-safe: confine an instance to the single serial queue that delivers capture callbacks.
public final class AudioIngestPipeline {
    public static let errorDomain = "AudioIngestPipeline"

    public enum ErrorCode: Int {
        case unsupportedSampleFormat = 1
        case missingFormatDescription = 2
        /// `CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer` failed; the OSStatus is in the description.
        case bufferListUnavailable = 3
    }

    private let recorder: DiagnosticsRecorder
    private let rawDump: RawDumpSink?
    /// The dump starts at the first non-silent buffer: runs begin with the operator still in our app, where
    /// capture is digital silence (F-007), so a dump from t = 0 would hold nothing useful.
    private var rawDumpArmed = false
    private let maxChannels: Int
    private let bufferList: UnsafeMutableAudioBufferListPointer
    private let bufferListCapacity: Int
    private var lastASBD: AudioStreamBasicDescription?
    private var lastFormat: AudioFormatInfo?
    /// Exact list size CoreMedia needs for the current format. It must be exact: a larger size fails with
    /// kCMSampleBufferError_ArrayTooSmall (-12737) on the 27.0 SDKs (see FINDINGS).
    private var neededListSize: Int?
    /// Errors are recorded once per kind so a persistent fault cannot grow the report per buffer.
    private var reportedErrors: Set<Int> = []

    /// `maxChannels` bounds the preallocated buffer list (one entry per channel when non-interleaved).
    public init(recorder: DiagnosticsRecorder, rawDump: RawDumpSink? = nil, maxChannels: Int = 8) {
        self.recorder = recorder
        self.rawDump = rawDump
        self.maxChannels = maxChannels
        bufferList = AudioBufferList.allocate(maximumBuffers: maxChannels)
        bufferListCapacity = AudioBufferList.sizeInBytes(maximumBuffers: maxChannels)
    }

    deinit {
        free(bufferList.unsafeMutablePointer)
    }

    public func ingest(_ sampleBuffer: CMSampleBuffer, type: ProbeReport.BufferType) {
        // Video and microphone buffers are only counted (spec 001 §4.2/§4.4).
        guard type == .audio || type == .audioApp else {
            recorder.recordBuffer(type)
            return
        }
        guard let format = format(of: sampleBuffer) else {
            recorder.recordBuffer(type)
            reportOnce(.missingFormatDescription, "audio buffer without an audio format description")
            return
        }
        guard format.sampleFormat != .unsupported else {
            recorder.recordBuffer(type)
            reportOnce(.unsupportedSampleFormat, "unsupported PCM layout: \(format)")
            return
        }
        guard let level = measure(sampleBuffer, format: format) else {
            recorder.recordBuffer(type)
            return
        }
        if let rawDump {
            if !rawDumpArmed, !level.isSilent() { rawDumpArmed = true }
            if rawDumpArmed { rawDump.append(sampleBuffer) }
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        recorder.recordAudio(
            type, format: format, frameCount: CMSampleBufferGetNumSamples(sampleBuffer),
            presentationTimeSec: pts.isValid ? pts.seconds : nil, level: level)
    }

    // MARK: - Private

    /// Rebuilds `AudioFormatInfo` only when the ASBD changes (building it allocates a string).
    private func format(of sampleBuffer: CMSampleBuffer) -> AudioFormatInfo? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return nil
        }
        if let lastASBD, let lastFormat, Self.isEqual(lastASBD, asbd) {
            return lastFormat
        }
        let format = AudioFormatInfo(asbd)
        lastASBD = asbd
        lastFormat = format
        neededListSize = nil
        return format
    }

    private func measure(_ sampleBuffer: CMSampleBuffer, format: AudioFormatInfo) -> LevelMeasurement? {
        guard let listSize = listSize(for: sampleBuffer, format: format) else { return nil }
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: bufferList.unsafeMutablePointer,
            bufferListSize: listSize, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer)
        guard status == noErr else {
            reportOnce(.bufferListUnavailable, "audio buffer list unavailable (OSStatus \(status), "
                       + "\(format.channels) ch)")
            return nil
        }
        // `blockBuffer` keeps the PCM alive until this function returns.
        var accumulator = LevelAccumulator()
        for buffer in bufferList {
            guard let data = buffer.mData else { continue }
            switch format.sampleFormat {
            case .int16:
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int16.self), count: count)
                accumulator.add(int16: samples)
            case .float32:
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
                accumulator.add(float32: samples)
            case .unsupported:
                return nil
            }
        }
        return accumulator.measurement
    }

    /// Queried once per format; nil (and reported) if the format needs more buffers than were preallocated.
    private func listSize(for sampleBuffer: CMSampleBuffer, format: AudioFormatInfo) -> Int? {
        if let neededListSize { return neededListSize }
        var needed = 0
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard status == noErr, needed > 0, needed <= bufferListCapacity else {
            reportOnce(.bufferListUnavailable, "audio buffer list unavailable (OSStatus \(status), needs \(needed) "
                       + "bytes for \(format.channels) ch, capacity \(maxChannels) buffers)")
            return nil
        }
        neededListSize = needed
        return needed
    }

    private func reportOnce(_ code: ErrorCode, _ description: @autoclosure () -> String) {
        guard reportedErrors.insert(code.rawValue).inserted else { return }
        recorder.recordError(domain: Self.errorDomain, code: code.rawValue, description: description())
    }

    private static func isEqual(_ lhs: AudioStreamBasicDescription, _ rhs: AudioStreamBasicDescription) -> Bool {
        lhs.mSampleRate == rhs.mSampleRate && lhs.mFormatID == rhs.mFormatID && lhs.mFormatFlags == rhs.mFormatFlags
            && lhs.mBytesPerPacket == rhs.mBytesPerPacket && lhs.mFramesPerPacket == rhs.mFramesPerPacket
            && lhs.mBytesPerFrame == rhs.mBytesPerFrame && lhs.mChannelsPerFrame == rhs.mChannelsPerFrame
            && lhs.mBitsPerChannel == rhs.mBitsPerChannel
    }
}
