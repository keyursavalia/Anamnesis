#if DEBUG
import AnamnesisKit
import Foundation
import Observation

// SPIKE: Lab → Test B (spec 004). Runs are JSON files in Documents/Eval/ (excluded from backup).
@Observable
final class EvalViewModel {
    struct Progress: Equatable {
        var index: Int
        var total: Int
        var clipID: String
        var configName: String
    }

    let corpus: CorpusStore
    var sweep: ExperimentSweep = .baselineOnly
    private(set) var runs: [EvalRun] = []
    private(set) var activeRunID: String?
    private(set) var progress: Progress?
    private(set) var lastError: String?

    private let runner: EvalRunner
    private let log: AppLog
    private let runsDirectory: URL?
    private var task: Task<Void, Never>?

    init(environment: AppEnvironment) {
        log = environment.log(.lab)
        corpus = CorpusStore(log: environment.log(.lab))
        runner = EvalRunner(service: TranscriptionService(log: environment.log(.transcribe)),
                            log: environment.log(.lab))
        runsDirectory = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true))
            .map { $0.appending(path: "Eval") }
    }

    var isRunning: Bool { activeRunID != nil }

    func load() async {
        await corpus.reload()
        guard let runsDirectory else { return }
        runs = await Task.detached { Self.loadRuns(in: runsDirectory) }.value
    }

    func startRun() {
        guard !corpus.clips.isEmpty else { return }
        let now = Date.now
        let format = Date.ISO8601FormatStyle().year().month().day().dateTimeSeparator(.standard)
            .time(includingFractionalSeconds: false)
        let id = now.formatted(format)
            .replacingOccurrences(of: ":", with: "")
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let version = "\(short) (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let run = EvalRun(id: id, createdAt: now, device: .current(), appVersion: version, sweep: sweep.rawValue,
                          configs: sweep.configs, clips: corpus.clips)
        runs.insert(run, at: 0)
        resume(run)
    }

    func resume(_ run: EvalRun) {
        guard !isRunning, let location = corpus.location, let url = fileURL(run) else { return }
        lastError = nil
        do {
            try Self.prepare(directory: url.deletingLastPathComponent())
            try run.jsonData().write(to: url, options: .atomic)
        } catch {
            lastError = error.localizedDescription
            return
        }
        activeRunID = run.id
        let stream = runner.run(run, corpus: location, saveTo: url)
        task = Task {
            defer {
                activeRunID = nil
                progress = nil
            }
            do {
                for try await event in stream {
                    switch event {
                    case .job(let index, let total, let clipID, let configName):
                        progress = Progress(index: index, total: total, clipID: clipID, configName: configName)
                    case .result: break
                    case .saved(let saved): replace(saved)
                    }
                }
            } catch is CancellationError {
                log.notice("eval run=\(run.id) paused")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Pauses: finished jobs are saved; the current one runs again on resume.
    func cancel() {
        task?.cancel()
    }

    func delete(_ run: EvalRun) {
        guard run.id != activeRunID, let url = fileURL(run) else { return }
        try? FileManager.default.removeItem(at: url)
        runs.removeAll { $0.id == run.id }
    }

    /// Not while the run is active: the runner's copy would overwrite the rating on its next save.
    func setRating(runID: String, clipID: String, configName: String, rating: Int, minutesToFix: Double?) {
        guard runID != activeRunID, var run = runs.first(where: { $0.id == runID }), let url = fileURL(run) else {
            return
        }
        run.setRating(EvalRating(clipID: clipID, configName: configName, rating: rating, minutesToFix: minutesToFix,
                                 ratedAt: .now))
        do {
            try run.jsonData().write(to: url, options: .atomic)
            replace(run)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func run(id: String) -> EvalRun? { runs.first { $0.id == id } }
    func truth(_ clip: CorpusClip) -> String? { corpus.location?.truth(clip) }

    /// R9: `wer-<date>.csv`, `results-<date>.json`, `ratings-<date>.csv` in tmp for `ShareLink`.
    func exportURLs(_ run: EvalRun) -> [URL] {
        let directory = FileManager.default.temporaryDirectory
        let files: [(String, () throws -> Data)] = [
            ("wer-\(run.id).csv", { Data(EvalReport.werCSV(run).utf8) }),
            ("results-\(run.id).json", { try run.jsonData() }),
            ("ratings-\(run.id).csv", { Data(EvalReport.ratingsCSV(run).utf8) })
        ]
        return files.compactMap { name, data in
            let url = directory.appending(path: name)
            do {
                try data().write(to: url, options: .atomic)
                return url
            } catch {
                log.error("eval export \(name) failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func replace(_ run: EvalRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.insert(run, at: 0)
        }
    }

    private func fileURL(_ run: EvalRun) -> URL? {
        runsDirectory?.appending(path: "run-\(run.id).json")
    }

    private nonisolated static func prepare(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private nonisolated static func loadRuns(in directory: URL) -> [EvalRun] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? EvalRun.decode(Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
#endif
