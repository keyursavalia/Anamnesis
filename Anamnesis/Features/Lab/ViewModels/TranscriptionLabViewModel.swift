#if DEBUG
import AnamnesisKit
import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

// SPIKE: Lab → Transcription (spec 003 R1, R10, R11, Step 8 switches).
@Observable
final class TranscriptionLabViewModel {
    enum ModuleChoice: String, CaseIterable, Identifiable {
        case speechTranscriber = "SpeechTranscriber"
        case dictationLong = "Dictation · long"
        case dictationTimeIndexed = "Dictation · time-indexed"
        var id: Self { self }
    }

    /// How an imported audio-only file is read (Step 8 comparison); video always uses the asset provider.
    enum AudioReader: String, CaseIterable, Identifiable {
        case audioFile = "AVAudioFile"
        case assetProvider = "AssetInputSequenceProvider"
        var id: Self { self }
    }

    enum JobState: Equatable {
        case idle
        case running(source: String)
        case finished
        case failed(String)
    }

    private static let localeKey = "lab.transcription.locale"

    var localeID: String {
        didSet { UserDefaults.standard.set(localeID, forKey: Self.localeKey) }
    }
    var module: ModuleChoice = .speechTranscriber
    var detector: TranscriptionConfig.Sensitivity?
    var audioReader: AudioReader = .audioFile
    var momentConfig = MomentConfig()
    var lineBreakConfig = LineBreakConfig()

    let assets: AssetManager
    private(set) var job: JobState = .idle
    private(set) var audioSec: Double?
    private(set) var analyzerFormat: String?
    private(set) var liveSegments: [TranscriptSegment] = []
    private(set) var speechRegionCount = 0
    private(set) var transcript: Transcript?

    private let service: TranscriptionService
    private let log: AppLog
    private var task: Task<Void, Never>?
    /// Bumped per job so a cancelled job that resumes late cannot overwrite the next job's state.
    private var generation = 0

    init(environment: AppEnvironment) {
        log = environment.log(.lab)
        assets = AssetManager(log: environment.log(.transcribe))
        service = TranscriptionService(log: environment.log(.transcribe))
        localeID = UserDefaults.standard.string(forKey: Self.localeKey) ?? "en_US"
    }

    var locale: Locale { Locale(identifier: localeID) }
    var isRunning: Bool { if case .running = job { true } else { false } }

    var config: TranscriptionConfig {
        let module: TranscriptionConfig.Module = switch self.module {
        case .speechTranscriber: .speechTranscriber(etiquetteReplacements: false)
        case .dictationLong: .dictation(.longDictation)
        case .dictationTimeIndexed: .dictation(.timeIndexedLongDictation)
        }
        return TranscriptionConfig(module: module, speechDetector: detector)
    }

    func load() async {
        await assets.loadLocales()
        await assets.refresh(locale: locale, config: config)
    }

    func refreshAssets() async { await assets.refresh(locale: locale, config: config) }
    func installAssets() async { await assets.install(locale: locale, config: config) }

    // MARK: - Jobs

    /// Imported files are copied into the sandbox under security scope and deleted after the job (spec 003 §4).
    func importFile(_ result: Result<URL, any Error>) {
        do {
            let picked = try result.get()
            let copy = try Self.copyIntoSandbox(picked)
            let isVideo = (try? copy.resourceValues(forKeys: [.contentTypeKey]).contentType)?
                .conforms(to: .movie) ?? false
            let useAsset = isVideo || audioReader == .assetProvider
            let input: TranscriptionInput = useAsset ? .mediaAsset(copy) : .audioFile(copy)
            start(input) { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        } catch {
            job = .failed("Import failed: \(error.localizedDescription)")
        }
    }

    func transcribe(session: SpoolSession) {
        start(.session(session)) {}
    }

    func cancel() {
        task?.cancel()
    }

    private func start(_ input: TranscriptionInput, cleanup: @escaping () -> Void) {
        task?.cancel()
        generation += 1
        let current = generation
        job = .running(source: input.sourceName)
        audioSec = nil
        analyzerFormat = nil
        liveSegments = []
        speechRegionCount = 0
        transcript = nil
        let stream = service.transcribe(input, locale: locale, config: config)
        task = Task {
            defer { cleanup() }
            do {
                for try await event in stream where current == generation { handle(event) }
                guard current == generation else { return }
                // A cancelled stream ends without throwing.
                job = transcript != nil ? .finished : .failed(TranscriptionError.cancelled.localizedDescription)
            } catch {
                guard current == generation else { return }
                job = .failed(error.localizedDescription)
                log.error("transcription job failed: \(error.localizedDescription)")
            }
        }
    }

    private func handle(_ event: TranscriptEvent) {
        switch event {
        case .started(let audioSec, let format):
            self.audioSec = audioSec
            analyzerFormat = format
        case .segment(let segment): liveSegments.append(segment)
        case .speech: speechRegionCount += 1
        case .finished(let transcript): self.transcript = transcript
        }
    }

    // MARK: - Export

    func copyText(poem: Bool) {
        guard let transcript else { return }
        UIPasteboard.general.string = poem ? transcript.poemText(config: lineBreakConfig) : transcript.plainText
    }

    /// `ShareLink` needs a file so the owner receives a `.json`. Transcript text stays on device unless the owner
    /// shares it; never commit it (CLAUDE.md §12).
    func exportURL() -> URL? {
        guard let transcript else { return nil }
        let stamp = transcript.createdAt
            .formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory.appending(path: "transcript-\(stamp).json")
        do {
            try transcript.jsonData().write(to: url, options: .atomic)
            return url
        } catch {
            log.error("transcript export failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func copyIntoSandbox(_ picked: URL) throws -> URL {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: picked.lastPathComponent)
        try FileManager.default.copyItem(at: picked, to: copy)
        return copy
    }
}
#endif
