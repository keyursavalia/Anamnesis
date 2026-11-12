#if DEBUG
import AnamnesisKit
import Foundation
import Observation

/// Where the corpus lives on disk. Sendable so the runner actor can resolve clip and truth files.
nonisolated struct CorpusLocation: Sendable {
    let root: URL

    var clipsURL: URL { root.appending(path: "clips") }
    var truthURL: URL { root.appending(path: "truth") }
    var metaURL: URL { root.appending(path: "meta.csv") }

    func clipURL(_ clip: CorpusClip) -> URL { clipsURL.appending(path: clip.clipFile) }

    func truth(_ clip: CorpusClip) -> String? {
        clip.truthFile.flatMap { try? String(contentsOf: truthURL.appending(path: $0), encoding: .utf8) }
    }

    func index() -> (clips: [CorpusClip], issues: [CorpusIssue]) {
        CorpusIndex.build(clipFiles: Self.files(in: clipsURL), truthFiles: Self.files(in: truthURL),
                          metaCSV: try? String(contentsOf: metaURL, encoding: .utf8))
    }

    private static func files(in directory: URL) -> [CorpusIndex.File] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return CorpusIndex.File(name: url.lastPathComponent, size: values?.fileSize ?? 0)
        }
    }
}

// SPIKE: Test B corpus (spec 004 R1). One corpus at a time in Documents/Corpus/, excluded from backup.
// Corpus files are copyrighted recitals and the owner's truth text: never logged, never committed.
@Observable
final class CorpusStore {
    private(set) var clips: [CorpusClip] = []
    private(set) var issues: [CorpusIssue] = []
    private(set) var lastError: String?

    let location: CorpusLocation?
    private let log: AppLog

    init(log: AppLog) {
        self.log = log
        location = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            .map { CorpusLocation(root: $0.appending(path: "Corpus")) }
    }

    func reload() async {
        guard let location else { return }
        let (clips, issues) = await Task.detached { location.index() }.value
        self.clips = clips
        self.issues = issues
    }

    /// Replaces the corpus with a picked folder containing `clips/`, `truth/` and optionally `meta.csv`.
    func importFolder(_ result: Result<URL, any Error>) async {
        guard let location else { return }
        lastError = nil
        do {
            let folder = try result.get()
            try await Task.detached { try Self.copy(folder, to: location) }.value
            await reload()
            log.notice("corpus imported clips=\(clips.count) issues=\(issues.count)")
        } catch {
            lastError = error.localizedDescription
            log.error("corpus import failed: \(error.localizedDescription)")
        }
    }

    var clipsByCategory: [(category: String, count: Int)] {
        Dictionary(grouping: clips) { $0.category ?? "?" }.map { ($0.key, $0.value.count) }.sorted { $0.0 < $1.0 }
    }

    private nonisolated static func copy(_ folder: URL, to location: CorpusLocation) throws {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.appending(path: "clips").path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey:
                "The folder needs a clips/ subfolder (and truth/ with <clip>.txt files)."])
        }
        if manager.fileExists(atPath: location.root.path(percentEncoded: false)) {
            try manager.removeItem(at: location.root)
        }
        try manager.createDirectory(at: location.root, withIntermediateDirectories: true)
        var root = location.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        for name in ["clips", "truth", "meta.csv"] {
            let source = folder.appending(path: name)
            if manager.fileExists(atPath: source.path(percentEncoded: false)) {
                try manager.copyItem(at: source, to: location.root.appending(path: name))
            }
        }
    }
}
#endif
