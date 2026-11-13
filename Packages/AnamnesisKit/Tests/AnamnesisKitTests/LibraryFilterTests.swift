import Foundation
import SwiftData
import Testing
@testable import AnamnesisKit

@Suite("Library filter and search")
struct LibraryFilterTests {
    let start = Date(timeIntervalSince1970: 1_794_000_000)

    /// Three poems, oldest first: "über die Nacht" by Rilke, "Café" (titled) by nobody, "a quiet road" by Anon.
    func makeStore() throws -> ModelContext {
        let context = ModelContext(try ModelContainer.library(at: nil))
        let rilke = Poem(body: "über die Nacht\nzweite Zeile", createdAt: start)
        rilke.poet = "Rilke"
        rilke.tags = ["Night"]
        let cafe = Poem(body: "morning light", createdAt: start.addingTimeInterval(10))
        cafe.title = "Café"
        cafe.tags = ["love", "night"]
        let road = Poem(body: "\n  a quiet road\nends here", createdAt: start.addingTimeInterval(20))
        road.poet = "Anon"
        for poem in [rilke, cafe, road] { context.insert(poem) }
        try context.save()
        return context
    }

    func titles(_ context: ModelContext, _ filter: LibraryFilter) throws -> [String] {
        let fetched = try context.fetch(FetchDescriptor<Poem>(predicate: filter.predicate))
        return filter.refine(fetched).map(\.displayTitle)
    }

    @Test("search matches body, title and poet, ignoring case and diacritics; empty matches all")
    func search() throws {
        let context = try makeStore()
        #expect(try titles(context, LibraryFilter(searchText: "UBER")) == ["über die Nacht"])
        #expect(try titles(context, LibraryFilter(searchText: " cafe ")) == ["Café"])
        #expect(try titles(context, LibraryFilter(searchText: "rilke")) == ["über die Nacht"])
        #expect(try titles(context, LibraryFilter(searchText: "zzz")).isEmpty)
        #expect(try titles(context, LibraryFilter()) == ["a quiet road", "Café", "über die Nacht"])
    }

    @Test("poet and tag filters combine with search")
    func filters() throws {
        let context = try makeStore()
        #expect(try titles(context, LibraryFilter(poet: "Anon")) == ["a quiet road"])
        #expect(try titles(context, LibraryFilter(tag: "night")) == ["Café", "über die Nacht"])
        #expect(try titles(context, LibraryFilter(searchText: "light", tag: "NIGHT")) == ["Café"])
        #expect(LibraryFilter(tag: "x").isFiltering)
        #expect(!LibraryFilter(searchText: "  ").isFiltering)
    }

    @Test("sorts: newest, title (first line when untitled), poet with none last")
    func sorts() throws {
        let context = try makeStore()
        #expect(try titles(context, LibraryFilter(sort: .title)) == ["a quiet road", "Café", "über die Nacht"])
        #expect(try titles(context, LibraryFilter(sort: .poet)) == ["a quiet road", "über die Nacht", "Café"])
    }

    @Test("menus list distinct tags and poets")
    func menus() throws {
        let poems = try makeStore().fetch(FetchDescriptor<Poem>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(LibraryFilter.tags(in: poems) == ["love", "Night"])
        #expect(LibraryFilter.poets(in: poems) == ["Anon", "Rilke"])
        #expect(poems[2].firstLines(2) == "a quiet road / ends here")
    }

    @Test("search over 200 poems stays well under 200 ms (AC1, loose bound)")
    func timing() throws {
        let context = ModelContext(try ModelContainer.library(at: nil))
        for index in 0..<200 {
            let poem = Poem(body: "line \(index) of the evening\nwith words \(index) and more", createdAt: start)
            poem.poet = index % 3 == 0 ? "Poet \(index)" : nil
            context.insert(poem)
        }
        try context.save()
        let filter = LibraryFilter(searchText: "words 17")
        var found: [Poem] = []
        let elapsed = try ContinuousClock().measure {
            found = filter.refine(try context.fetch(FetchDescriptor<Poem>(predicate: filter.predicate)))
        }
        #expect(found.count == 11)
        #expect(elapsed < .milliseconds(200))
    }

    @Test("deleting a poem keeps its Moment saved without a poem (AC2)")
    func deletePoem() throws {
        let context = ModelContext(try ModelContainer.library(at: nil))
        let draft = MomentDraft(index: 0, startSec: 0, endSec: 1, text: "a", poemText: "a", meanConfidence: nil,
                                flags: [], segmentsData: Data("[]".utf8))
        let moment = MomentRecord(draft)
        context.insert(moment)
        let poem = moment.saveAsPoem(in: context)
        try context.save()
        context.delete(poem)
        try context.save()
        #expect(moment.review == .saved)
        #expect(moment.poem == nil)
        #expect(try context.fetchCount(FetchDescriptor<Poem>()) == 0)
    }
}
