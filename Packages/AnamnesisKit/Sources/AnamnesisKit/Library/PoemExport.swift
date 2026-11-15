import Foundation

/// A poem as plain values for Copy and the share card (spec 014 R1; spec 016 R6 removed Markdown and tags).
public struct PoemExport: Sendable, Equatable {
    public var title: String?
    public var poet: String?
    public var body: String
    public var sourceNote: String?

    public init(title: String? = nil, poet: String? = nil, body: String, sourceNote: String? = nil) {
        self.title = title
        self.poet = poet
        self.body = body
        self.sourceNote = sourceNote
    }

    public init(poem: Poem) {
        self.init(title: poem.title, poet: poem.poet, body: poem.body, sourceNote: poem.sourceNote)
    }

    /// The title, else the first non-empty line.
    public var heading: String {
        if let title, !title.isEmpty { return title }
        return body.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "Poem"
    }

    /// Title, "— Poet", the body, and the source on its own line.
    public var plainText: String {
        var header = [title, poet.map { "— \($0)" }].compactMap(\.self).joined(separator: "\n")
        if !header.isEmpty { header += "\n\n" }
        return header + body + (sourceNote.map { "\n\nSource: " + $0 } ?? "")
    }
}
