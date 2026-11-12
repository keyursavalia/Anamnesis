#if DEBUG
import AnamnesisKit
import Foundation

// SPIKE: Test B batch runner (spec 004 R2). Serial jobs (one SpeechAnalyzer at a time, per Speech resource
// limits); the run file is rewritten after every job so a run resumes after relaunch.
actor EvalRunner {
    enum Event: Sendable {
        case job(index: Int, total: Int, clipID: String, configName: String)
        case result(EvalResult)
        /// The run file after the last saved job.
        case saved(EvalRun)
    }

    private let service: TranscriptionService
    private let log: AppLog

    init(service: TranscriptionService, log: AppLog) {
        self.service = service
        self.log = log
    }

    nonisolated func run(_ run: EvalRun, corpus: CorpusLocation, saveTo url: URL)
        -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.execute(run, corpus: corpus, saveTo: url, events: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(_ initial: EvalRun, corpus: CorpusLocation, saveTo url: URL,
                         events: AsyncThrowingStream<Event, any Error>.Continuation) async throws {
        var run = initial
        let total = run.totalJobs
        let scratch = FileManager.default.temporaryDirectory.appending(path: "Eval-\(run.id)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        log.notice("eval run=\(run.id) start pending=\(run.pendingJobs.count)/\(total)")
        for job in run.pendingJobs {
            try Task.checkCancellation()
            events.yield(.job(index: total - run.pendingJobs.count + 1, total: total, clipID: job.clip.id,
                              configName: job.config.name))
            let result = await evaluate(job, corpus: corpus, scratch: scratch)
            // A job cut short by cancel is not recorded, so it stays pending for the resume.
            try Task.checkCancellation()
            run.results.append(result)
            try run.jsonData().write(to: url, options: .atomic)
            log.notice("eval run=\(run.id) clip=\(job.clip.id) config=\(job.config.name) "
                       + "wer=\(result.scores?.wer?.wer.map { String(format: "%.3f", $0) } ?? "-") "
                       + "error=\(result.error ?? "none")")
            events.yield(.result(result))
            events.yield(.saved(run))
        }
        log.notice("eval run=\(run.id) finished results=\(run.results.count)")
    }

    private func evaluate(_ job: EvalRun.Job, corpus: CorpusLocation, scratch: URL) async -> EvalResult {
        let clip = job.clip
        func failed(_ message: String) -> EvalResult {
            EvalResult(clipID: clip.id, category: clip.category, configName: job.config.name, finishedAt: .now,
                       transcript: nil, scores: nil, error: message)
        }
        do {
            let input = try Self.input(for: clip, config: job.config, corpus: corpus, scratch: scratch)
            var transcript: Transcript?
            for try await event in service.transcribe(input, locale: Locale(identifier: job.config.locale),
                                                      config: job.config.transcription) {
                if case .finished(let finished) = event { transcript = finished }
            }
            guard let transcript else { return failed("no transcript") }
            let scores = EvalScoring.score(transcript: transcript, truth: corpus.truth(clip),
                                           isHallucinationClip: clip.isHallucinationClip,
                                           lineBreaks: job.config.lineBreaks)
            return EvalResult(clipID: clip.id, category: clip.category, configName: job.config.name,
                              finishedAt: .now, transcript: transcript, scores: scores, error: nil)
        } catch {
            return failed(error.localizedDescription)
        }
    }

    private static func input(for clip: CorpusClip, config: ExperimentConfig, corpus: CorpusLocation,
                              scratch: URL) throws -> TranscriptionInput {
        let url = corpus.clipURL(clip)
        if let rate = config.audioFormat.sampleRate {
            return .audioFile(try AudioReencoder.reencode(url, sampleRate: rate, into: scratch))
        }
        let isVideo = CorpusIndex.videoExtensions.contains(url.pathExtension.lowercased())
        return isVideo ? .mediaAsset(url) : .audioFile(url)
    }
}
#endif
