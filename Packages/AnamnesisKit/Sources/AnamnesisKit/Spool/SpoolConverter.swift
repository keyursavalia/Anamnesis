import AVFAudio

/// Writer-queue side of format conversion (spec 002 R1): interleaved Float32 at any rate/channel count →
/// interleaved Float32 at the spool rate/channel count. Passthrough when they already match (SCK at 16 kHz mono,
/// F-006); otherwise one `AVAudioConverter` per input format, rebuilt on change. Quantizing to Int16 happens in
/// the writer so clipping can be counted. Not thread-safe: confine to the writer queue.
final class SpoolConverter {
    struct InputKey: Equatable {
        var sampleRate: Double
        var channels: Int
    }

    private let spool: SpoolFormat
    private let maxInputSamples: Int
    private(set) var input: InputKey?
    private var converter: AVAudioConverter?
    private var inputBuffer: AVAudioPCMBuffer?
    private var outputBuffer: AVAudioPCMBuffer?

    init(spool: SpoolFormat, maxInputSamples: Int) {
        self.spool = spool
        self.maxInputSamples = maxInputSamples
    }

    /// Rebuilds the converter for a new input format. Audio still buffered in the old converter (a few ms of
    /// resampler latency) is discarded: format changes are rare and already counted.
    func setInput(_ key: InputKey) throws(SpoolError) {
        guard key != input else { return }
        input = key
        converter = nil
        inputBuffer = nil
        outputBuffer = nil
        guard key.sampleRate != spool.sampleRate || key.channels != spool.channels else { return }
        guard let from = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: key.sampleRate,
                channels: AVAudioChannelCount(key.channels), interleaved: true),
              let target = spool.floatFormat,
              let converter = AVAudioConverter(from: from, to: target),
              let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: from, frameCapacity: AVAudioFrameCount(maxInputSamples / key.channels)) else {
            throw .converterUnavailable("\(key.sampleRate) Hz \(key.channels) ch")
        }
        converter.downmix = true
        let outputFrames = Double(inputBuffer.frameCapacity) * spool.sampleRate / key.sampleRate
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: target, frameCapacity: AVAudioFrameCount(outputFrames.rounded(.up)) + 1_024) else {
            throw .converterUnavailable("output buffer")
        }
        self.converter = converter
        self.inputBuffer = inputBuffer
        self.outputBuffer = outputBuffer
    }

    /// Hands spool-format samples to `emit`, possibly in several calls (or none while the resampler primes).
    func convert(
        _ samples: UnsafePointer<Float>, frames: Int, emit: (UnsafeBufferPointer<Float>) throws(SpoolError) -> Void
    ) throws(SpoolError) {
        guard let input else { throw .converterUnavailable("no input format") }
        guard let converter, let inputBuffer, let outputBuffer else {
            try emit(UnsafeBufferPointer(start: samples, count: frames * input.channels))
            return
        }
        // Safe: both formats are Float32, so `floatChannelData` exists; interleaved → one buffer.
        inputBuffer.floatChannelData.unsafelyUnwrapped[0].update(from: samples, count: frames * input.channels)
        inputBuffer.frameLength = AVAudioFrameCount(frames)
        var provided = false
        while true {
            outputBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
                guard !provided else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                provided = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            if status == .error { throw .conversionFailed(error?.localizedDescription ?? "unknown") }
            let produced = Int(outputBuffer.frameLength) * spool.channels
            if produced > 0 {
                let output = outputBuffer.floatChannelData.unsafelyUnwrapped[0]
                try emit(UnsafeBufferPointer(start: output, count: produced))
            }
            // `.haveData` means the output filled up; anything else means the input is consumed.
            guard status == .haveData else { return }
        }
    }
}

public enum SpoolError: Error, LocalizedError, Equatable {
    case converterUnavailable(String)
    case conversionFailed(String)
    case fileFailed(String)

    public var errorDescription: String? {
        switch self {
        case .converterUnavailable(let detail): "No converter for \(detail)"
        case .conversionFailed(let detail): "Conversion failed: \(detail)"
        case .fileFailed(let detail): "Segment file failed: \(detail)"
        }
    }
}
