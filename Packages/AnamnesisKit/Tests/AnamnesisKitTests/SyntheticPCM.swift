import AVFAudio
import AudioToolbox
import Foundation
@testable import AnamnesisKit

/// Synthetic audio (CONVENTIONS §9: no real recordings) and helpers to feed it to the spool writer as a
/// capture callback would: an `AudioBufferList` that is only valid for the call.
enum SyntheticPCM {
    /// Deterministic, full-range, non-periodic pattern: any lost, duplicated or reordered sample changes it.
    static func pattern(count: Int, seed: Int = 0) -> [Int16] {
        (0..<count).map { Int16(truncatingIfNeeded: ($0 + seed) &* 7_919 &+ ($0 >> 3)) }
    }

    static func sine(frames: Int, channels: Int = 1, sampleRate: Double, frequency: Double = 440,
                     amplitude: Float = 0.5) -> [Float] {
        (0..<frames * channels).map { index in
            amplitude * Float(sin(2 * .pi * frequency * Double(index / channels) / sampleRate))
        }
    }

    static func formatInfo(
        sampleRate: Double, channels: UInt32, float: Bool, interleaved: Bool
    ) -> AnamnesisKit.AudioFormatInfo {
        AnamnesisKit.AudioFormatInfo(SampleBufferFactory.makeASBD(
            sampleRate: sampleRate, channels: channels, bits: float ? 32 : 16,
            flags: (float ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger) | kAudioFormatFlagIsPacked,
            interleaved: interleaved))
    }

    /// Reads every segment of a session back as one Int16 array (mono or interleaved).
    static func readAll(_ session: SpoolSession) throws -> [Int16] {
        var result: [Int16] = []
        for (_, url) in session.segmentFiles() {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
            let frames = AVAudioFrameCount(file.length)
            guard frames > 0 else { continue }
            let buffer = try requireBuffer(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
            try file.read(into: buffer)
            let samples = Int(buffer.frameLength) * Int(buffer.format.channelCount)
            result += UnsafeBufferPointer(start: buffer.int16ChannelData?[0], count: samples)
        }
        return result
    }

    struct MissingBuffer: Error {}

    private static func requireBuffer(_ buffer: AVAudioPCMBuffer?) throws -> AVAudioPCMBuffer {
        guard let buffer else { throw MissingBuffer() }
        return buffer
    }
}

extension SegmentedSpoolWriter {
    func enqueue(int16 samples: [Int16], channels: UInt32 = 1, sampleRate: Double = 16_000, pts: Double? = nil) {
        let format = SyntheticPCM.formatInfo(
            sampleRate: sampleRate, channels: channels, float: false, interleaved: true)
        let frames = samples.count / Int(channels)
        var samples = samples
        samples.withUnsafeMutableBytes { bytes in
            enqueueRaw(buffers: [bytes], channelsPerBuffer: channels, format: format, frames: frames, pts: pts)
        }
    }

    func enqueue(float32 samples: [Float], sampleRate: Double = 16_000, pts: Double? = nil) {
        let format = SyntheticPCM.formatInfo(sampleRate: sampleRate, channels: 1, float: true, interleaved: true)
        let frames = samples.count
        var samples = samples
        samples.withUnsafeMutableBytes { bytes in
            enqueueRaw(buffers: [bytes], channelsPerBuffer: 1, format: format, frames: frames, pts: pts)
        }
    }

    func enqueue(planar channels: [[Float]], sampleRate: Double, pts: Double? = nil) {
        let format = SyntheticPCM.formatInfo(
            sampleRate: sampleRate, channels: UInt32(channels.count), float: true, interleaved: false)
        var left = channels[0]
        var right = channels[1]
        left.withUnsafeMutableBytes { leftBytes in
            right.withUnsafeMutableBytes { rightBytes in
                enqueueRaw(buffers: [leftBytes, rightBytes], channelsPerBuffer: 1, format: format,
                        frames: channels[0].count, pts: pts)
            }
        }
    }

    private func enqueueRaw(
        buffers: [UnsafeMutableRawBufferPointer], channelsPerBuffer: UInt32, format: AnamnesisKit.AudioFormatInfo,
        frames: Int, pts: Double?
    ) {
        let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        defer { free(list.unsafeMutablePointer) }
        for (index, bytes) in buffers.enumerated() {
            list[index] = AudioBuffer(
                mNumberChannels: channelsPerBuffer, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
        }
        enqueue(list.unsafePointer, format: format, frames: frames, pts: pts)
    }
}
