#if DEBUG
import AnamnesisKit
import AVFAudio
import Foundation

// SPIKE: spec 004 R10 / D-006 — re-encode a clip to mono Int16 PCM at a fixed rate before transcribing, so
// spool-format choices can be compared on the same corpus. Streams ~0.5 s chunks; never loads the whole clip.
nonisolated enum AudioReencoder {
    static func reencode(_ source: URL, sampleRate: Double, into directory: URL) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1,
                                         interleaved: true),
              let converter = AVAudioConverter(from: input.processingFormat, to: target) else {
            throw TranscriptionError.fileUnreadable("no converter for \(source.lastPathComponent)")
        }
        converter.downmix = true
        let stem = source.deletingPathExtension().lastPathComponent
        let output = directory.appending(path: "\(stem)-\(Int(sampleRate)).caf")
        let file = try AVAudioFile(forWriting: output, settings: target.settings, commonFormat: .pcmFormatInt16,
                                   interleaved: true)
        let inFrames = AVAudioFrameCount(input.processingFormat.sampleRate / 2)
        let outFrames = AVAudioFrameCount(sampleRate / 2) + 1_024
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: inFrames),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else {
            throw TranscriptionError.fileUnreadable("cannot allocate conversion buffers")
        }
        var inputDone = false
        var readError: (any Error)?
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
                // Check the position first: on MP4 input, reading at the end throws eofErr (-39, F-025)
                // instead of returning 0 frames.
                if inputDone || input.framePosition >= input.length {
                    inputDone = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.read(into: inBuffer, frameCount: inFrames)
                } catch {
                    readError = error
                }
                if readError != nil || inBuffer.frameLength == 0 {
                    inputDone = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inBuffer
            }
            if let error = conversionError ?? readError { throw error }
            if outBuffer.frameLength > 0 { try file.write(from: outBuffer) }
            if status == .endOfStream || status == .error { break }
        }
        file.close()
        return output
    }
}
#endif
