import AnamnesisKit
import AVFoundation
import CoreMedia
import Foundation
import Speech

/// What a job reads. Imported files are already copied into the sandbox by the caller.
nonisolated enum TranscriptionInput: Sendable {
    /// Read with `analyzeSequence(from: AVAudioFile)`.
    case audioFile(URL)
    /// Any audio/video asset (e.g. a screen recording) through iOS 27 `AssetInputSequenceProvider`.
    case mediaAsset(URL)
    /// A spool session as one timeline (`SpoolAnalyzerInputSequence`).
    case session(SpoolSession)

    var sourceName: String {
        switch self {
        case .audioFile(let url), .mediaAsset(let url): url.lastPathComponent
        case .session(let session): "session \(session.id)"
        }
    }
}

nonisolated enum TranscriptEvent: Sendable {
    case started(audioSec: Double, analyzerFormat: String?)
    case segment(TranscriptSegment)
    case speech(SpeechRegion)
    case finished(Transcript)
}

/// Runs transcription jobs with `SpeechAnalyzer` (spec 003 R2, ARCHITECTURE §5.1). One analyzer per job; result
/// consumers start before audio is fed; cancelling the stream cancels the job.
actor TranscriptionService {
    typealias Events = AsyncThrowingStream<TranscriptEvent, any Error>.Continuation

    private let log: AppLog

    init(log: AppLog) {
        self.log = log
    }

    nonisolated func transcribe(_ input: TranscriptionInput, locale: Locale, config: TranscriptionConfig)
        -> AsyncThrowingStream<TranscriptEvent, any Error> {
        AsyncThrowingStream { continuation in
            let job = Task {
                do {
                    let transcript = try await self.run(input, locale: locale, config: config,
                                                        events: continuation)
                    continuation.yield(.finished(transcript))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? TranscriptionError.cancelled
                                                                   : TranscriptionError(error))
                }
            }
            continuation.onTermination = { _ in job.cancel() }
        }
    }

    private func run(_ input: TranscriptionInput, locale: Locale, config: TranscriptionConfig,
                     events: Events) async throws -> Transcript {
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.transcriberUnavailable }
        guard let resolved = await TranscriptionModules.supportedLocale(equivalentTo: locale, config: config) else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        let status = await AssetInventory.status(
            forModules: TranscriptionModules(locale: resolved, config: config).transcriberOnly)
        guard status == .installed else { throw TranscriptionError.modelNotInstalled(status: status.name) }
        log.notice("transcribe start source=\(input.sourceName) locale=\(resolved.identifier) module=\(config.module) "
                   + "detector=\(config.speechDetector?.rawValue ?? "off")")
        do {
            return try await analyze(input, locale: resolved, config: config, assetStatus: status, events: events)
        } catch where TranscriptionError(error).speechCode == .assetLocaleNotAllocated {
            // R1: reserve only when the analyzer asks for it, then retry once.
            log.notice("transcribe reserving locale=\(resolved.identifier) after assetLocaleNotAllocated")
            try await AssetInventory.reserve(locale: resolved)
            return try await analyze(input, locale: resolved, config: config, assetStatus: status, events: events)
        }
    }

    private func analyze(_ input: TranscriptionInput, locale: Locale, config: TranscriptionConfig,
                         assetStatus: AssetInventory.Status,
                         events: Events) async throws -> Transcript {
        let modules = TranscriptionModules(locale: locale, config: config)
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules.all)
        let formatText = format?.shortDescription
        let formatSpec = format.map(SpoolAnalyzerInputSequence.FormatSpec.init)
        let analyzer = SpeechAnalyzer(modules: modules.all, options: TranscriptionModules.analyzerOptions(config))

        let started = ContinuousClock.now
        let memory = Self.peakFootprintSampler()
        let segments = Self.collectSegments(modules.transcriber, events: events)
        let regions = modules.detector.map { Self.collectRegions($0, events: events) }
        defer {
            memory.cancel()
            segments.cancel()
            regions?.cancel()
        }

        let audioSec = try await withTaskCancellationHandler {
            do {
                let audioSec = try await Self.audioDuration(of: input)
                events.yield(.started(audioSec: audioSec, analyzerFormat: formatText))
                try await Self.feed(input, to: analyzer, modules: modules, analyzerFormat: formatSpec)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return audioSec
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
        // `analyzeSequence` may return normally after `cancelAndFinishNow`; never report a partial job as done.
        try Task.checkCancellation()
        let collected = try await segments.value
        let speechRegions = try await regions?.value
        if let speechRegions { log.notice("detector regions=\(speechRegions.count)") }
        let wallSec = Self.seconds(ContinuousClock.now - started)
        memory.cancel()
        let metrics = TranscriptionMetrics(audioSec: audioSec, wallSec: wallSec, assetStatus: assetStatus.name,
                                           peakFootprintMB: await memory.value, analyzerFormat: formatText)
        log.notice("transcribe done segments=\(collected.count) audio=\(Self.format(audioSec))s "
                   + "wall=\(Self.format(wallSec))s rtf=\(metrics.realTimeFactor.map(Self.format) ?? "-") "
                   + "peakMB=\(metrics.peakFootprintMB.map(Self.format) ?? "-") format=\(formatText ?? "nil")")
        return Transcript(source: input.sourceName, locale: locale.identifier, config: config, createdAt: .now,
                          segments: collected, speechRegions: speechRegions, metrics: metrics)
    }

    // MARK: - Feeding

    private static func feed(_ input: TranscriptionInput, to analyzer: SpeechAnalyzer, modules: TranscriptionModules,
                             analyzerFormat: SpoolAnalyzerInputSequence.FormatSpec?) async throws {
        switch input {
        case .audioFile(let url):
            let file: AVAudioFile
            do { file = try AVAudioFile(forReading: url) } catch {
                throw TranscriptionError.fileUnreadable("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            _ = try await analyzer.analyzeSequence(from: file)
        case .mediaAsset(let url):
            let provider = try await AssetInputSequenceProvider.provider(from: AVURLAsset(url: url),
                                                                         compatibleWith: modules.all)
            _ = try await analyzer.analyzeSequence(provider.analyzerInputs)
        case .session(let session):
            let reader = try SpoolReader(session: session)
            _ = try await analyzer.analyzeSequence(
                SpoolAnalyzerInputSequence(reader: reader, analyzerFormat: analyzerFormat))
        }
    }

    private static func audioDuration(of input: TranscriptionInput) async throws -> Double {
        switch input {
        case .audioFile(let url):
            let file: AVAudioFile
            do { file = try AVAudioFile(forReading: url) } catch {
                throw TranscriptionError.fileUnreadable("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            return Double(file.length) / file.processingFormat.sampleRate
        case .mediaAsset(let url):
            return try await AVURLAsset(url: url).load(.duration).seconds
        case .session(let session):
            let reader = try SpoolReader(session: session)
            return reader.manifest.format.seconds(forFrames: reader.totalFrames)
        }
    }

    // MARK: - Results

    private static func collectSegments(_ transcriber: TranscriptionModules.Transcriber,
                                        events: Events)
        -> Task<[TranscriptSegment], any Error> {
        Task {
            var segments: [TranscriptSegment] = []
            func add(_ text: AttributedString, _ range: CMTimeRange) {
                guard let segment = segment(text: text, range: range) else { return }
                segments.append(segment)
                events.yield(.segment(segment))
            }
            switch transcriber {
            case .speech(let module):
                for try await result in module.results where result.isFinal { add(result.text, result.range) }
            case .dictation(let module):
                for try await result in module.results where result.isFinal { add(result.text, result.range) }
            }
            return segments
        }
    }

    private static func collectRegions(_ detector: SpeechDetector,
                                       events: Events)
        -> Task<[SpeechRegion], any Error> {
        Task {
            var regions: [SpeechRegion] = []
            // Not filtered on `isFinal`; overlapping results are merged when coverage is computed. On iOS 27 (iPad)
            // the detector reported no results at all, filtered or not (F-026).
            for try await result in detector.results {
                let region = SpeechRegion(startSec: result.range.start.seconds, endSec: result.range.end.seconds,
                                          speechDetected: result.speechDetected)
                regions.append(region)
                events.yield(.speech(region))
            }
            return regions
        }
    }

    /// Copies a result's attributed runs into plain values; the pure mapping lives in AnamnesisKit.
    static func segment(text: AttributedString, range: CMTimeRange) -> TranscriptSegment? {
        let runs = text.runs.map { run in
            let timeRange = run.audioTimeRange
            return TranscriptRun(text: String(text[run.range].characters), startSec: timeRange?.start.seconds,
                                 endSec: timeRange?.end.seconds, confidence: run.transcriptionConfidence)
        }
        return TranscriptSegment(runs: runs, resultStartSec: range.start.seconds, resultEndSec: range.end.seconds)
    }

    // MARK: - Metrics

    private static func peakFootprintSampler() -> Task<Double?, Never> {
        Task(priority: .utility) {
            var peak: Double?
            while !Task.isCancelled {
                if let reading = MemorySampler.read() { peak = max(peak ?? 0, reading.physFootprintMB) }
                try? await Task.sleep(for: .milliseconds(500))
            }
            return peak
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
