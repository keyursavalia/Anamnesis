import Foundation

/// One Test B clip (spec 004 R1). `id` is the basename shared by `clips/<id>.<ext>` and `truth/<id>.txt`.
public struct CorpusClip: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var clipFile: String
    /// nil when no truth file exists (the clip still runs; it just gets no WER).
    public var truthFile: String?
    /// TESTING §4.1: A–F, or M for music/silence (hallucination test).
    public var category: String?
    public var language: String?
    public var notes: String?

    public init(id: String, clipFile: String, truthFile: String?, category: String? = nil, language: String? = nil,
                notes: String? = nil) {
        self.id = id
        self.clipFile = clipFile
        self.truthFile = truthFile
        self.category = category
        self.language = language
        self.notes = notes
    }

    public var isHallucinationClip: Bool { category == "M" }
}

public struct CorpusIssue: Sendable, Equatable, Codable {
    public enum Problem: String, Sendable, Codable {
        case missingTruth, truthWithoutClip, unsupportedFormat, emptyFile, duplicateClip, badMetaRow, unknownMetaClip
    }

    public var file: String
    public var problem: Problem

    public init(file: String, problem: Problem) {
        self.file = file
        self.problem = problem
    }
}

/// Pairs files and metadata into clips; pure so the validation report is unit-tested (spec 004 Step 2).
public enum CorpusIndex {
    public static let clipExtensions: Set<String> = ["m4a", "wav", "caf", "mp4", "mov"]
    public static let videoExtensions: Set<String> = ["mp4", "mov"]

    public struct File: Sendable, Equatable {
        public var name: String
        public var size: Int

        public init(name: String, size: Int) {
            self.name = name
            self.size = size
        }
    }

    /// An empty truth file is valid for category M (the expected transcript is nothing).
    public static func build(clipFiles: [File], truthFiles: [File], metaCSV: String?)
        -> (clips: [CorpusClip], issues: [CorpusIssue]) {
        var issues: [CorpusIssue] = []
        let (meta, metaIssues) = metaCSV.map(parseMeta) ?? ([:], [])
        issues += metaIssues
        let truthByID = Dictionary(truthFiles.filter { ext($0.name) == "txt" }.map { (stem($0.name), $0) },
                                   uniquingKeysWith: { first, _ in first })
        var clips: [CorpusClip] = []
        var seen: Set<String> = []
        for file in clipFiles.sorted(by: { $0.name < $1.name }) where !file.name.hasPrefix(".") {
            guard clipExtensions.contains(ext(file.name)) else {
                issues.append(CorpusIssue(file: file.name, problem: .unsupportedFormat))
                continue
            }
            guard file.size > 0 else {
                issues.append(CorpusIssue(file: file.name, problem: .emptyFile))
                continue
            }
            let id = stem(file.name)
            guard seen.insert(id).inserted else {
                issues.append(CorpusIssue(file: file.name, problem: .duplicateClip))
                continue
            }
            let row = meta[id]
            let truth = truthByID[id]
            if truth == nil { issues.append(CorpusIssue(file: file.name, problem: .missingTruth)) }
            if let truth, truth.size == 0, row?.category != "M" {
                issues.append(CorpusIssue(file: truth.name, problem: .emptyFile))
            }
            clips.append(CorpusClip(id: id, clipFile: file.name, truthFile: truth?.name, category: row?.category,
                                    language: row?.language, notes: row?.notes))
        }
        for id in truthByID.keys.sorted() where !seen.contains(id) {
            issues.append(CorpusIssue(file: "\(id).txt", problem: .truthWithoutClip))
        }
        for id in meta.keys.sorted() where !seen.contains(id) {
            issues.append(CorpusIssue(file: "meta.csv: \(id)", problem: .unknownMetaClip))
        }
        return (clips, issues)
    }

    struct MetaRow: Equatable {
        var category: String?
        var language: String?
        var notes: String?
    }

    /// `clip,category,language,notes` with a header row; `clip` may include the extension. Quoted fields with
    /// commas and doubled quotes are supported.
    static func parseMeta(_ text: String) -> ([String: MetaRow], [CorpusIssue]) {
        var rows: [String: MetaRow] = [:]
        var issues: [CorpusIssue] = []
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for (number, line) in lines.enumerated() {
            let fields = csvFields(line).map { $0.trimmingCharacters(in: .whitespaces) }
            if number == 0, fields.first?.lowercased() == "clip" { continue }
            guard let clip = fields.first, !clip.isEmpty else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    issues.append(CorpusIssue(file: "meta.csv line \(number + 1)", problem: .badMetaRow))
                }
                continue
            }
            func field(_ index: Int) -> String? { index < fields.count && !fields[index].isEmpty ? fields[index] : nil }
            rows[clipExtensions.contains(ext(clip)) ? stem(clip) : clip] =
                MetaRow(category: field(1)?.uppercased(), language: field(2), notes: field(3))
        }
        return (rows, issues)
    }

    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var characters = Array(line)[...]
        while let character = characters.popFirst() {
            if quoted {
                if character == "\"" {
                    if characters.first == "\"" {
                        current.append("\"")
                        characters.removeFirst()
                    } else {
                        quoted = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }
    static func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }
}
