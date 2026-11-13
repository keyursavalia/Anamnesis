import Foundation
import Testing
@testable import AnamnesisKit

@Suite("Poem export")
struct PoemExportTests {
    /// The paragraphs Foundation's Markdown parser reads back, in order (hard breaks come back as `\n`).
    static func paragraphs(_ markdown: String) throws -> [String] {
        let parsed = try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full))
        var result: [(Int, String)] = []
        for run in parsed.runs {
            let identity = run.presentationIntent?.components.first?.identity ?? -1
            let text = String(parsed[run.range].characters)
            if let last = result.last, last.0 == identity {
                result[result.count - 1].1 += text
            } else {
                result.append((identity, text))
            }
        }
        return result.map(\.1)
    }

    @Test("lines and stanzas round-trip through Markdown, markup characters included (AC1)")
    func roundTrip() throws {
        let body = """
            # not a heading
            - not a list, 1. nor *this* or _that_
            1. not numbered \\ back[slash] <tag> & ~~x~~ | !

              ---
            last stanza line one
            """ + "\n\n\nfinal line"
        let expected = [
            "# not a heading\n- not a list, 1. nor *this* or _that_\n1. not numbered \\ back[slash] <tag> & ~~x~~ | !",
            "---\nlast stanza line one",
            "final line"
        ]
        #expect(try Self.paragraphs(MarkdownEscaping.body(body)) == expected)
    }

    @Test("a shared poem has its title, poet, body, source and tags")
    func poemMarkdown() throws {
        let poem = PoemExport(title: "Night *Song*", poet: "A. Poet", body: "one\ntwo\n\nthree",
                              sourceNote: "Instagram reel", tags: ["love", "night"])
        #expect(try Self.paragraphs(poem.markdown)
                == ["Night *Song*", "A. Poet", "one\ntwo", "three", "Source: Instagram reel", "Tags: love, night"])
        #expect(poem.markdown.hasPrefix("# Night \\*Song\\*\n\n*A. Poet*\n\n"))
    }

    @Test("plain text puts title and poet above the body and the details below")
    func plainText() {
        let full = PoemExport(title: "T", poet: "P", body: "a\nb", sourceNote: "reel", tags: ["x"])
        #expect(full.plainText == "T\n— P\n\na\nb\n\nSource: reel\nTags: x")
        #expect(PoemExport(body: "a\nb").plainText == "a\nb")
    }

    @Test("file names come from the title or first line, without unsafe characters")
    func fileNames() {
        #expect(PoemExport(title: "What/is: love?", body: "x").fileName == "Whatis love.md")
        #expect(PoemExport(body: "\n  first line\nsecond").fileName == "first line.md")
        #expect(PoemExport(body: "").fileName == "Poem.md")
        #expect(PoemExport(title: String(repeating: "a", count: 80), body: "x").fileName.count == 63)
    }

    @Test("the library file has one section per poem")
    func library() throws {
        let poems = [PoemExport(title: "First", body: "a\nb"), PoemExport(poet: "P", body: "c\n\nd")]
        let markdown = PoemExport.libraryMarkdown(poems, exportedAt: Date(timeIntervalSince1970: 1_794_000_000))
        let paragraphs = try Self.paragraphs(markdown)
        #expect(paragraphs.first == "Anamnesis library")
        #expect(paragraphs.contains("2 poems.") || paragraphs[1].hasSuffix("2 poems."))
        // Foundation reads the `---` between poems as a "⸻" paragraph.
        #expect(Array(paragraphs.suffix(7)) == ["First", "a\nb", "⸻", "c", "P", "c", "d"])
    }
}
