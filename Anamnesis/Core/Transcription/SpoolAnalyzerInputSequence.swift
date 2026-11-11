import AnamnesisKit
import AVFAudio
import CoreMedia
import Speech

/// Feeds a spool session to `SpeechAnalyzer` as one continuous timeline (spec 003 R4): segments in order,
/// ~0.5 s per buffer pulled on demand (never the whole session), `bufferStartTime` from a gap-free sample clock.
nonisolated struct SpoolAnalyzerInputSequence: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput

    /// `AVAudioFormat` is not Sendable; keep its plain parts and rebuild it in the iterator.
    struct FormatSpec: Sendable, Equatable {
        var commonFormat: AVAudioCommonFormat
        var sampleRate: Double
        var channels: AVAudioChannelCount
        var interleaved: Bool

        init(_ format: AVAudioFormat) {
            commonFormat = format.commonFormat
            sampleRate = format.sampleRate
            channels = format.channelCount
            interleaved = format.isInterleaved
        }

        var format: AVAudioFormat? {
            AVAudioFormat(commonFormat: commonFormat, sampleRate: sampleRate, channels: channels,
                          interleaved: interleaved)
        }
    }

    let reader: SpoolReader
    /// nil or equal to the spool format = pass through; otherwise `AnalyzerInputConverter` converts.
    let analyzerFormat: FormatSpec?

    func makeAsyncIterator() -> Iterator {
        Iterator(cursor: reader.makeCursor(), analyzerFormat: analyzerFormat)
    }

    struct Iterator: AsyncIteratorProtocol {
        private var cursor: SpoolReader.Cursor
        private let frameCapacity: AVAudioFrameCount
        private let sampleRate: Double
        private var converter: AnalyzerInputConverter?
        private var pending: [AnalyzerInput] = []
        private var finished = false

        init(cursor: SpoolReader.Cursor, analyzerFormat: FormatSpec?) {
            self.cursor = cursor
            sampleRate = cursor.processingFormat.sampleRate
            frameCapacity = AVAudioFrameCount(sampleRate / 2)
            if let analyzerFormat, analyzerFormat != FormatSpec(cursor.processingFormat),
               let format = analyzerFormat.format {
                converter = AnalyzerInputConverter(analyzerFormat: format)
            }
        }

        mutating func next() async throws -> AnalyzerInput? {
            while pending.isEmpty, !finished {
                try Task.checkCancellation()
                // A fresh buffer per input: the analyzer may still hold the previous one.
                guard let buffer = AVAudioPCMBuffer(pcmFormat: cursor.processingFormat, frameCapacity: frameCapacity)
                else { throw TranscriptionError.fileUnreadable("cannot allocate a spool buffer") }
                if let chunk = try cursor.read(into: buffer) {
                    pending = try inputs(for: buffer, timelineFrame: chunk.timelineFrame)
                } else {
                    finished = true
                    pending = try converter?.flush() ?? []
                }
            }
            return pending.isEmpty ? nil : pending.removeFirst()
        }

        private func inputs(for buffer: AVAudioPCMBuffer, timelineFrame: Int) throws -> [AnalyzerInput] {
            guard let converter else {
                let start = CMTime(value: CMTimeValue(timelineFrame), timescale: CMTimeScale(sampleRate))
                return [AnalyzerInput(buffer: buffer, bufferStartTime: start)]
            }
            // [UNVERIFIED] that the converter carries `at` into `bufferStartTime`; F-004 says the analyzer wants
            // the spool format, so this path should not run. Log it if it does (FINDINGS).
            return try converter.convert(buffer, at: AVAudioTime(sampleTime: AVAudioFramePosition(timelineFrame),
                                                                 atRate: sampleRate))
        }
    }
}
