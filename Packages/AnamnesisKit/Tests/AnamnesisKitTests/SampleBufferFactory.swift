import AudioToolbox
import CoreMedia
import Foundation

/// Builds real audio `CMSampleBuffer`s from known PCM so the ingest path is tested like a capture callback.
enum SampleBufferFactory {
    struct FactoryError: Error {
        let step: String
        let status: OSStatus
    }

    static func int16Interleaved(
        _ samples: [Int16], channels: UInt32 = 1, sampleRate: Double = 16_000, pts: Double = 0
    ) throws -> CMSampleBuffer {
        let asbd = makeASBD(
            sampleRate: sampleRate, channels: channels, bits: 16,
            flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, interleaved: true)
        let bytes = samples.withUnsafeBytes { Data($0) }
        return try make(asbd: asbd, frames: samples.count / Int(channels), pts: pts, channelData: [bytes])
    }

    static func float32Planar(
        _ channels: [[Float]], sampleRate: Double = 48_000, pts: Double = 0
    ) throws -> CMSampleBuffer {
        let asbd = makeASBD(
            sampleRate: sampleRate, channels: UInt32(channels.count), bits: 32,
            flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, interleaved: false)
        let data = channels.map { channel in channel.withUnsafeBytes { Data($0) } }
        return try make(asbd: asbd, frames: channels.first?.count ?? 0, pts: pts, channelData: data)
    }

    static func int32Interleaved(
        _ samples: [Int32], sampleRate: Double = 16_000, pts: Double = 0
    ) throws -> CMSampleBuffer {
        let asbd = makeASBD(
            sampleRate: sampleRate, channels: 1, bits: 32,
            flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, interleaved: true)
        let bytes = samples.withUnsafeBytes { Data($0) }
        return try make(asbd: asbd, frames: samples.count, pts: pts, channelData: [bytes])
    }

    static func makeASBD(
        sampleRate: Double, channels: UInt32, bits: UInt32, flags: AudioFormatFlags, interleaved: Bool
    ) -> AudioStreamBasicDescription {
        let bytesPerFrame = (bits / 8) * (interleaved ? channels : 1)
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels, mBitsPerChannel: bits, mReserved: 0)
    }

    private static func make(
        asbd: AudioStreamBasicDescription, frames: Int, pts: Double, channelData: [Data]
    ) throws -> CMSampleBuffer {
        var asbd = asbd
        var format: CMAudioFormatDescription?
        try check("format", CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format))
        var sampleBuffer: CMSampleBuffer?
        try check("sampleBuffer", CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format!, sampleCount: frames,
            presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 1_000_000),
            packetDescriptions: nil, sampleBufferOut: &sampleBuffer))

        let list = AudioBufferList.allocate(maximumBuffers: channelData.count)
        // CoreMedia copies the bytes into its own block buffer, so these are freed right after.
        let storage = channelData.map { data in
            let pointer = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 16)
            data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: data.count)
            return (pointer, data.count)
        }
        defer {
            storage.forEach { $0.0.deallocate() }
            free(list.unsafeMutablePointer)
        }
        let channelsPerBuffer = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 1 : asbd.mChannelsPerFrame
        for (index, (pointer, count)) in storage.enumerated() {
            list[index] = AudioBuffer(mNumberChannels: channelsPerBuffer, mDataByteSize: UInt32(count), mData: pointer)
        }
        try check("setData", CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            bufferList: list.unsafePointer))
        return sampleBuffer!
    }

    private static func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw FactoryError(step: step, status: status) }
    }
}
