import AVFAudio

/// On-disk format of spooled audio (D-006): linear PCM Int16, little-endian, interleaved, in CAF segments.
public struct SpoolFormat: Sendable, Equatable, Codable {
    /// 16 kHz mono Int16, 60-s segments (≈ 1.92 MB per segment). Matches the analyzer's preferred format (F-004).
    public static let standard = SpoolFormat(sampleRate: 16_000, channels: 1, segmentSeconds: 60)

    public var sampleRate: Double
    public var channels: Int
    public var segmentSeconds: Int

    public init(sampleRate: Double, channels: Int, segmentSeconds: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.segmentSeconds = segmentSeconds
    }

    /// Rotation point; segments are split exactly here (spec 002 R2).
    public var segmentFrames: Int { Int(sampleRate) * segmentSeconds }

    public var bytesPerFrame: Int { channels * MemoryLayout<Int16>.size }

    public func seconds(forFrames frames: Int) -> Double { Double(frames) / sampleRate }

    /// The in-memory format the writer hands to `AVAudioFile`; nil only for impossible values (0 Hz, 0 channels).
    var pcmFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: AVAudioChannelCount(channels),
            interleaved: true)
    }

    /// Float32 at the spool rate and channel count: what the resampler produces before quantizing to Int16.
    var floatFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels),
            interleaved: true)
    }
}
