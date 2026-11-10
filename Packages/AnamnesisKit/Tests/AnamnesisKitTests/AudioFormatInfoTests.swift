import CoreAudioTypes
import Testing
@testable import AnamnesisKit

@Suite("AudioFormatInfo")
struct AudioFormatInfoTests {
    static func asbd(
        rate: Double, channels: UInt32, bits: UInt32, flags: AudioFormatFlags, interleaved: Bool = true
    ) -> AudioStreamBasicDescription {
        let bytesPerSample = bits / 8
        let bytesPerFrame = interleaved ? bytesPerSample * channels : bytesPerSample
        return AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels, mBitsPerChannel: bits, mReserved: 0)
    }

    @Test("describes 16 kHz mono Int16 interleaved")
    func int16Mono() {
        let info = AudioFormatInfo(Self.asbd(
            rate: 16_000, channels: 1, bits: 16, flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked))
        #expect(info.sampleRate == 16_000)
        #expect(info.channels == 1)
        #expect(info.bitsPerChannel == 16)
        #expect(info.formatID == "lpcm")
        #expect(info.isInterleaved)
        #expect(info.sampleFormat == .int16)
    }

    @Test("describes 48 kHz stereo Float32 non-interleaved")
    func floatStereoPlanar() {
        let info = AudioFormatInfo(Self.asbd(
            rate: 48_000, channels: 2, bits: 32, flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            interleaved: false))
        #expect(!info.isInterleaved)
        #expect(info.sampleFormat == .float32)
    }

    @Test("unsupported PCM layouts are flagged", arguments: [
        (UInt32(24), kAudioFormatFlagIsSignedInteger), (UInt32(32), kAudioFormatFlagIsSignedInteger),
        (UInt32(64), kAudioFormatFlagIsFloat), (UInt32(16), AudioFormatFlags(0)),
        (UInt32(16), kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian)
    ])
    func unsupported(bits: UInt32, flags: AudioFormatFlags) {
        let info = AudioFormatInfo(Self.asbd(rate: 44_100, channels: 1, bits: bits, flags: flags))
        #expect(info.sampleFormat == .unsupported)
    }

    @Test("equal ASBDs compare equal, a rate change does not")
    func equality() {
        let flags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        let stereo48k = AudioFormatInfo(Self.asbd(rate: 48_000, channels: 2, bits: 32, flags: flags))
        #expect(stereo48k == AudioFormatInfo(Self.asbd(rate: 48_000, channels: 2, bits: 32, flags: flags)))
        #expect(stereo48k != AudioFormatInfo(Self.asbd(rate: 44_100, channels: 2, bits: 32, flags: flags)))
    }
}
