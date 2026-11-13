import Foundation

/// A poem as plain values for sharing (spec 014 R1, PRD M7).
public struct PoemExport: Sendable, Equatable {
    public var title: String?
    public var poet: String?
    public var body: String
    public var sourceNote: String?
    public var tags: [String]

    public init(title: String? = nil, poet: String? = nil, body: String, sourceNote: String? = nil,
                tags: [String] = []) {
        self.title = title
        self.poet = poet
        self.body = body
        self.sourceNote = sourceNote
        self.tags = tags
    }

    public init(poem: Poem) {
        self.init(title: poem.title, poet: poem.poet, body: poem.body, sourceNote: poem.sourceNote, tags: poem.tags)
    }

    /// The title, else the first non-empty line.
    public var heading: String {
        if let title, !title.isEmpty { return title }
        return body.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "Poem"
    }

    public var plainText: String {
        var header = [title, poet.map { "— \($0)" }].compactMap(\.self).joined(separator: "\n")
        if !header.isEmpty { header += "\n\n" }
        return header + body + footer(sourcePrefix: "Source: ").map { "\n\n" + $0 }.joined()
    }

    /// `# Title`, `*Poet*`, the body (line breaks and stanzas kept), source and tags.
    public var markdown: String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append("# " + MarkdownEscaping.line(title)) }
        parts.append(contentsOf: markdownSection())
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// e.g. `The Road Not Taken.md`.
    public var fileName: String {
        let unsafe = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines).union(.controlCharacters)
        let cleaned = String(heading.unicodeScalars.filter { !unsafe.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        return String((cleaned.isEmpty ? "Poem" : cleaned).prefix(60)) + ".md"
    }

    /// Every poem as one Markdown file, a `##` section each.
    public static func libraryMarkdown(_ poems: [PoemExport], exportedAt: Date) -> String {
        let count = "\(poems.count) poem\(poems.count == 1 ? "" : "s")"
        var parts = ["# Anamnesis library",
                     "Exported " + exportedAt.formatted(date: .long, time: .omitted) + " · " + count + "."]
        for (index, poem) in poems.enumerated() {
            if index > 0 { parts.append("---") }
            parts.append("## " + MarkdownEscaping.line(poem.heading))
            parts.append(contentsOf: poem.markdownSection())
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// Poet, body, source and tags as Markdown blocks.
    func markdownSection() -> [String] {
        var parts: [String] = []
        if let poet, !poet.isEmpty { parts.append("*" + MarkdownEscaping.line(poet) + "*") }
        let body = MarkdownEscaping.body(body)
        if !body.isEmpty { parts.append(body) }
        if let sourceNote, !sourceNote.isEmpty { parts.append("> Source: " + MarkdownEscaping.line(sourceNote)) }
        if !tags.isEmpty { parts.append("Tags: " + MarkdownEscaping.line(PoemTags.format(tags))) }
        return parts
    }

    private func footer(sourcePrefix: String) -> [String] {
        let lines = [sourceNote.map { sourcePrefix + $0 }, tags.isEmpty ? nil : "Tags: " + PoemTags.format(tags)]
            .compactMap(\.self)
        return lines.isEmpty ? [] : [lines.joined(separator: "\n")]
    }
}

/// Poem text as CommonMark that reads back with the same lines and stanzas (spec 014 AC1).
public enum MarkdownEscaping {
    /// ASCII punctuation CommonMark may read as markup inside a line. All of it may be backslash-escaped.
    private static let inline: Set<Character> = ["\\", "*", "_", "`", "[", "]", "<", ">", "~", "&", "|", "!"]

    /// Lines of a stanza end in `\` (a hard break); stanzas are separated by one blank line. Leading spaces are
    /// dropped: CommonMark strips them inside a paragraph anyway, and four of them would start a code block.
    public static func body(_ text: String) -> String {
        var stanzas: [[String]] = [[]]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !(stanzas.last?.isEmpty ?? true) { stanzas.append([]) }
            } else {
                stanzas[stanzas.count - 1].append(Self.line(line))
            }
        }
        return stanzas.filter { !$0.isEmpty }.map { $0.joined(separator: "\\\n") }.joined(separator: "\n\n")
    }

    /// One line, safe from inline markup and from starting a heading, list, quote or rule.
    public static func line(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if inline.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        guard let first = escaped.first else { return escaped }
        let second = escaped.dropFirst().first
        let isRule = escaped.allSatisfy { $0 == "-" || $0 == "=" || $0 == " " }
        if first == "#" || isRule || ((first == "-" || first == "+") && (second == " " || second == nil)) {
            return "\\" + escaped
        }
        // `1. ` / `1) ` would start an ordered list.
        let digits = escaped.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let rest = escaped.dropFirst(digits.count)
            if let mark = rest.first, mark == "." || mark == ")" {
                return digits + "\\" + rest
            }
        }
        return escaped
    }
}
