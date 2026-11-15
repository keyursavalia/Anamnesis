import Foundation
import Testing
@testable import AnamnesisKit

@Suite("Poem export")
struct PoemExportTests {
    @Test("plain text puts title and poet above the body and the source below")
    func plainText() {
        let full = PoemExport(title: "T", poet: "P", body: "a\nb", sourceNote: "https://example.com/reel/1")
        #expect(full.plainText == "T\n— P\n\na\nb\n\nSource: https://example.com/reel/1")
        #expect(PoemExport(body: "a\nb").plainText == "a\nb")
        #expect(PoemExport(poet: "P", body: "a").plainText == "— P\n\na")
    }

    @Test("the heading is the title, else the first non-empty line")
    func heading() {
        #expect(PoemExport(title: "Night", body: "x").heading == "Night")
        #expect(PoemExport(title: "", body: "\n  first line\nsecond").heading == "first line")
        #expect(PoemExport(body: "").heading == "Poem")
    }
}
