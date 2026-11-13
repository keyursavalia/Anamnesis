import AnamnesisKit
import Foundation
import Observation
import UIKit

/// Transcribes finished capture sessions on its own (spec 008 R4): one job at a time, only with the app in front
/// (D-020), never while capturing. Writes `transcript.json` next to the spool session, imports it into the library
/// store (spec 009), then deletes the audio (D-010) unless the DEBUG keep-audio setting is on. A job the app dies in
/// leaves no transcript, so it reruns.
@Observable
final class TranscriptionQueue {
    enum JobState: Equatable {
        /// `processedSec`: end of the last final result, on the session's timeline.
        case running(processedSec: Double, audioSec: Double?)
        case failed(TranscriptionError)
    }

    /// English, D-011; the service resolves the device's equivalent locale.
    static let locale = Locale(identifier: "en_US")
    /// D-018 defaults: `SpeechTranscriber`, no detector (D-019).
    static let config = TranscriptionConfig()
    /// A session that failed this often is retried only by hand (spec 009); each launch tries again below it.
    static let maxAutomaticAttempts = 3

    /// Jobs this process ran or is running, by session id. Failures are also stored in the library.
    private(set) var jobs: [String: JobState] = [:]
    let assets: AssetManager

    #if DEBUG
    static let keepAudioKey = "debug.keepAudio"
    /// DEBUG only, on by default so excerpts can be played and evaluated (R7).
    var keepsAudio: Bool {
        didSet { UserDefaults.standard.set(keepsAudio, forKey: Self.keepAudioKey) }
    }
    #else
    /// Release follows D-010: audio is deleted after a successful transcription.
    let keepsAudio = false
    #endif

    private let sessions: SessionIngestor
    private let library: LibraryStore
    private let capture: CaptureController
    private let service: TranscriptionService
    private let log: AppLog
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runningID: String?
    /// Set when a capture start cancels the job, so the cancel is not reported as a failure.
    @ObservationIgnored private var cancelledForCapture = false
    /// Set between picking a session and starting its job, so two refreshes can't start two jobs.
    @ObservationIgnored private var isPicking = false
    /// Set while *Delete all data* runs (spec 013), so no job starts on files about to go.
    @ObservationIgnored private var isSuspended = false

    init(sessions: SessionIngestor, library: LibraryStore, capture: CaptureController, log: AppLog) {
        self.sessions = sessions
        self.library = library
        self.capture = capture
        self.log = log
        service = TranscriptionService(log: log)
        assets = AssetManager(log: log)
        #if DEBUG
        keepsAudio = UserDefaults.standard.object(forKey: Self.keepAudioKey) as? Bool ?? true
        #endif
    }

    func state(of id: String) -> JobState? { jobs[id] }

    /// After a spool refresh and library sync: stamps the first foreground after a stop (G5 latency) and starts the
    /// next job when the app is in front.
    func sessionsDidRefresh() async {
        let isActive = UIApplication.shared.applicationState == .active
        if isActive {
            let waiting = sessions.sessions.filter { $0.isDone && !$0.hasTranscript }.map(\.session)
            let log = log
            await Task.detached { Self.stampForeground(waiting, at: Date(), log: log) }.value
            await startNext()
        }
    }

    /// A capture started: free the analyzer for it; the job reruns from the start after the capture.
    func pauseForCapture() {
        guard let task, let runningID else { return }
        log.notice("transcription paused for capture session=\(runningID)")
        cancelledForCapture = true
        task.cancel()
    }

    func retry(_ id: String) async {
        jobs[id] = nil
        do {
            try await library.importer.clearFailure(sessionID: id)
        } catch {
            log.error("retry not stored session=\(id): \(error.localizedDescription)")
        }
        await startNext()
    }

    /// For a `modelNotInstalled` failure: the OS downloads the model (the only network use, R-11), then retries.
    func installModelAndRetry(_ id: String) async {
        await assets.install(locale: Self.locale, config: Self.config)
        await retry(id)
    }

    /// Swipe to delete: removes the session's folder (audio, transcript) and its library row; poems stay (R4).
    func delete(sessionID id: String) async throws {
        if runningID == id { task?.cancel() }
        jobs[id] = nil
        if let summary = sessions.sessions.first(where: { $0.id == id }) { try sessions.delete(summary) }
        try await library.importer.delete(sessionID: id)
    }

    /// *Delete all data* (spec 013 R3): stops the running job and waits for it, so nothing is written after the
    /// files go. Jobs stay off until `resume()`.
    func suspendForDeletion() async {
        isSuspended = true
        // Clearing `jobs` first makes the job's cancellation read as a deletion, not a failure.
        jobs = [:]
        if let task {
            task.cancel()
            await task.value
        }
        jobs = [:]
    }

    func resume() {
        isSuspended = false
    }

    // MARK: - Jobs

    private func startNext() async {
        guard task == nil, !isPicking, !isSuspended, !capture.isCapturing,
              UIApplication.shared.applicationState == .active else { return }
        isPicking = true
        defer { isPicking = false }
        let candidates: [String]
        do {
            candidates = try await library.importer.transcribableSessionIDs(maxAttempts: Self.maxAutomaticAttempts)
        } catch {
            log.error("transcription candidates unavailable: \(error.localizedDescription)")
            return
        }
        let summaries = Dictionary(sessions.sessions.map { ($0.id, $0) }) { first, _ in first }
        // Oldest first; the store's row is cross-checked with the folder, which must still hold audio.
        let next = candidates.lazy.compactMap { summaries[$0] }.first { summary in
            self.jobs[summary.id] == nil && summary.id != self.capture.activeSpoolSessionID
                && (summary.manifest?.totalFrames ?? 0) > 0
                && CaptureSessionState.isTranscribable(
                    isDone: summary.isDone, manifestState: summary.manifest?.state, hasAudio: summary.hasAudio,
                    hasTranscript: summary.hasTranscript)
        }
        // A capture may have started while the store was read.
        guard let next, task == nil, !capture.isCapturing else { return }
        run(next)
    }

    private func run(_ summary: SpoolSessionSummary) {
        let id = summary.id
        let session = summary.session
        let startedAt = Date()
        jobs[id] = .running(processedSec: 0, audioSec: summary.manifest?.durationSec)
        runningID = id
        cancelledForCapture = false
        log.notice("transcription job start session=\(id) audioSec=\(Int(summary.manifest?.durationSec ?? 0))")
        let stream = service.transcribe(.session(session), locale: Self.locale, config: Self.config)
        task = Task {
            do {
                var result: Transcript?
                for try await event in stream {
                    switch event {
                    case .started(let audioSec, _): jobs[id] = .running(processedSec: 0, audioSec: audioSec)
                    case .segment(let segment):
                        if case .running(_, let audioSec) = jobs[id] {
                            jobs[id] = .running(processedSec: segment.endSec, audioSec: audioSec)
                        }
                    case .speech: break
                    case .finished(let transcript): result = transcript
                    }
                }
                // A cancelled stream ends without throwing.
                guard let result else { throw TranscriptionError.cancelled }
                let (saved, audioDeleted) = try await Self.save(
                    result, session: session, startedAt: startedAt, deletingAudio: !keepsAudio, log: log)
                let outcome = try await library.importer.importTranscript(saved, audioDeleted: audioDeleted)
                jobs[id] = nil
                log.notice("transcription job done session=\(id) moments=\(saved.moments.count) "
                           + "jobSec=\(String(format: "%.1f", saved.metrics.jobSec)) "
                           + "latencySec=\(saved.metrics.latencySec.map { String(format: "%.1f", $0) } ?? "nil") "
                           + "audioDeleted=\(audioDeleted) import=\(outcome)")
            } catch {
                await handleFailure(error, id: id)
            }
            task = nil
            runningID = nil
            await sessions.refresh(activeSessionIDs: Set([capture.activeSpoolSessionID].compactMap(\.self)))
            await library.sync(with: sessions.sessions, log: log)
            await sessionsDidRefresh()
        }
    }

    private func handleFailure(_ error: any Error, id: String) async {
        let mapped = TranscriptionError(error)
        if mapped == .cancelled, cancelledForCapture || jobs[id] == nil {
            // Paused for a capture, or deleted: not a failure.
            jobs[id] = nil
            return
        }
        jobs[id] = .failed(mapped)
        log.error("transcription job failed session=\(id): \(mapped.localizedDescription)")
        do {
            try await library.importer.recordFailure(sessionID: id, text: mapped.localizedDescription)
        } catch {
            log.error("failure not stored session=\(id): \(error.localizedDescription)")
        }
    }

    /// Off the main actor: reads the capture record, writes the transcript atomically, then deletes the audio.
    /// Returns whether the audio is gone.
    private nonisolated static func save(
        _ transcript: Transcript, session: SpoolSession, startedAt: Date, deletingAudio: Bool, log: AppLog
    ) async throws -> (SessionTranscript, Bool) {
        try await Task.detached {
            let record = try? CaptureRecord.read(from: session.captureRecordURL)
            let metrics = SessionMetrics(capture: record, transcriptionStartedAt: startedAt, readyAt: Date(),
                                         audioSec: transcript.metrics?.audioSec ?? 0)
            let value = SessionTranscript(sessionID: session.id, transcript: transcript, metrics: metrics)
            try value.write(to: session.transcriptURL)
            guard deletingAudio else { return (value, false) }
            do {
                let removed = try session.deleteAudio()
                log.notice("audio deleted session=\(session.id) files=\(removed) (D-010)")
                return (value, true)
            } catch {
                log.error("audio not deleted session=\(session.id): \(error.localizedDescription)")
                return (value, !session.hasAudio)
            }
        }.value
    }

    private nonisolated static func stampForeground(_ waiting: [SpoolSession], at date: Date, log: AppLog) {
        for session in waiting {
            guard var record = try? CaptureRecord.read(from: session.captureRecordURL),
                  record.stoppedAt != nil, record.foregroundedAt == nil else { continue }
            record.markForegrounded(at: date)
            do {
                try record.write(to: session.captureRecordURL)
            } catch {
                log.error("foreground not recorded session=\(session.id): \(error.localizedDescription)")
            }
        }
    }
}
