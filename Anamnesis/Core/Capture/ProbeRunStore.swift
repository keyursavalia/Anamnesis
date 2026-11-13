import AnamnesisKit
import Foundation

// SPIKE: one folder per probe run under Application Support/Probes, holding the report JSON and optional raw.caf.
nonisolated struct ProbeRunStore: Sendable {
    let root: URL

    static func appDefault() throws -> ProbeRunStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ProbeRunStore(root: support.appending(path: "Probes"))
    }

    /// e.g. `20261109T171503Z_R-002-S1-C1-T2`.
    func makeRunDirectory(label: String, startedAt: Date) throws -> URL {
        // e.g. 20261109T171503Z (UTC, sortable, filename-safe).
        let stamp = startedAt.formatted(
            .iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false)
                .timeSeparator(.omitted))
        let directory = root.appending(path: "\(stamp)_\(Self.sanitized(label))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Matches the evidence naming `R-*_screenCaptureKit.json` (spec 001 §7).
    func reportURL(in directory: URL, label: String, backend: ProbeReport.Backend) -> URL {
        directory.appending(path: "\(Self.sanitized(label))_\(backend.rawValue).json")
    }

    func write(_ report: ProbeReport, to url: URL) throws {
        try report.jsonData().write(to: url, options: .atomic)
    }

    /// Runs on disk, newest first — including runs whose app was killed mid-capture (last periodic flush).
    func listRuns() -> [ProbeRun] {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        return directories.compactMap { directory -> ProbeRun? in
            guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
                  let reportURL = files.first(where: { $0.pathExtension == "json" }),
                  let data = try? Data(contentsOf: reportURL),
                  let report = try? ProbeReport.decode(from: data) else { return nil }
            let raw = files.first { $0.pathExtension == "caf" }
            return ProbeRun(directory: directory, reportURL: reportURL, rawDumpURL: raw, report: report)
        }
        .sorted { $0.report.startedAt > $1.report.startedAt }
    }

    /// Release keeps no probe reports (spec 014 R4): one run's folder after it finishes, or every run at launch.
    func remove(_ directory: URL) throws {
        try FileManager.default.removeItem(at: directory)
    }

    func removeAll() throws {
        try AppDataFiles.removeContents(of: root)
    }

    static func sanitized(_ label: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = label.trimmingCharacters(in: .whitespaces).unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(cleaned)
        return result.isEmpty ? "unlabeled" : result
    }
}
