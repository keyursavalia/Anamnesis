import CoreAudioTypes

/// Codable, comparable description of an `AudioStreamBasicDescription`, used in probe reports
/// and to detect mid-stream format changes (CONVENTIONS §3 rule 4).
public struct AudioFormatInfo: Sendable, Equatable, Codable {
    /// PCM layouts the ingest pipeline can measure without conversion.
    public enum SampleFormat: String, Sendable, Codable {
        case int16
        case float32
        case unsupported
    }

    public var sampleRate: Double
    public var channels: UInt32
    public var bitsPerChannel: UInt32
    /// Four-character code, e.g. "lpcm".
    public var formatID: String
    public var formatFlags: UInt32
    public var bytesPerFrame: UInt32
    public var isInterleaved: Bool
    public var sampleFormat: SampleFormat

    public init(_ asbd: AudioStreamBasicDescription) {
        sampleRate = asbd.mSampleRate
        channels = asbd.mChannelsPerFrame
        bitsPerChannel = asbd.mBitsPerChannel
        formatID = Self.fourCharacterCode(asbd.mFormatID)
        formatFlags = asbd.mFormatFlags
        bytesPerFrame = asbd.mBytesPerFrame
        isInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        sampleFormat = Self.sampleFormat(of: asbd)
    }

    private static func sampleFormat(of asbd: AudioStreamBasicDescription) -> SampleFormat {
        let flags = asbd.mFormatFlags
        // Measuring reads samples in native (little-endian) order.
        guard asbd.mFormatID == kAudioFormatLinearPCM, flags & kAudioFormatFlagIsBigEndian == 0 else {
            return .unsupported
        }
        if flags & kAudioFormatFlagIsFloat != 0 {
            return asbd.mBitsPerChannel == 32 ? .float32 : .unsupported
        }
        if flags & kAudioFormatFlagIsSignedInteger != 0, asbd.mBitsPerChannel == 16 {
            return .int16
        }
        return .unsupported
    }

    private static func fourCharacterCode(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return String(code) }
        return String(bytes: bytes, encoding: .ascii) ?? String(code)
    }
}
