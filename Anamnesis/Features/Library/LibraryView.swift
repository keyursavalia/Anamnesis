import AnamnesisKit
import SwiftData
import SwiftUI

/// Saved poems (spec 012, PRD M6): search as you type, poet and tag filters, sorts.
struct LibraryView: View {
    @State private var filter = LibraryFilter()
    /// All poems, for the filter menus and the "no poems yet" state.
    @Query private var allPoems: [Poem]

    var body: some View {
        NavigationStack {
            Group {
                if allPoems.isEmpty {
                    ContentUnavailableView {
                        Label("No poems yet", systemImage: "books.vertical")
                    } description: {
                        Text("Open a capture and tap Save as poem on a Moment. Saved poems appear here.")
                    }
                } else {
                    PoemListView(filter: filter)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Poem.self) { PoemDetailView(poem: $0) }
            .searchable(text: $filter.searchText, prompt: "Words, title or poet")
            .toolbar {
                if !allPoems.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        filterMenu
                        exportAll
                    }
                }
            }
        }
    }

    /// Every poem, newest first, as one Markdown file (spec 014 R1).
    private var exportAll: some View {
        let now = Date()
        let poems = allPoems.sorted { $0.createdAt > $1.createdAt }.map(PoemExport.init(poem:))
        let name = "Anamnesis Library " + now.formatted(.iso8601.year().month().day()) + ".md"
        return ShareLink(item: MarkdownFile(text: PoemExport.libraryMarkdown(poems, exportedAt: now), fileName: name),
                         preview: SharePreview(name)) {
            Label("Export all as Markdown", systemImage: "square.and.arrow.up.on.square")
        }
    }

    private var filterMenu: some View {
        let filtering = filter.tag != nil || filter.poet != nil
        return Menu {
            Picker("Sort", selection: $filter.sort) {
                Text("Newest").tag(LibrarySort.newest)
                Text("Title").tag(LibrarySort.title)
                Text("Poet").tag(LibrarySort.poet)
            }
            let poets = LibraryFilter.poets(in: allPoems)
            if !poets.isEmpty {
                Picker("Poet", selection: $filter.poet) {
                    Text("All poets").tag(String?.none)
                    ForEach(poets, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            let tags = LibraryFilter.tags(in: allPoems)
            if !tags.isEmpty {
                Picker("Tag", selection: $filter.tag) {
                    Text("All tags").tag(String?.none)
                    ForEach(tags, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label("Sort and filter", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill"
                                                           : "line.3.horizontal.decrease.circle")
        }
    }
}

/// The list for one filter. The store runs the search and poet predicate; tags and sorting run in memory (F-047).
private struct PoemListView: View {
    @Environment(\.modelContext) private var context
    let filter: LibraryFilter
    @Query private var matches: [Poem]
    @State private var pendingDelete: Poem?
    @State private var errorText: String?

    init(filter: LibraryFilter) {
        self.filter = filter
        _matches = Query(filter: filter.predicate, sort: \Poem.createdAt, order: .reverse)
    }

    var body: some View {
        let poems = filter.refine(matches)
        List {
            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            }
            ForEach(poems) { poem in
                NavigationLink(value: poem) { PoemRow(poem: poem) }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = poem }
                    }
            }
        }
        .overlay {
            if poems.isEmpty {
                if filter.query.isEmpty {
                    ContentUnavailableView("No matching poems", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("No poem has this poet and tag."))
                } else {
                    ContentUnavailableView.search(text: filter.query)
                }
            }
        }
        .confirmationDialog("Delete this poem?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete poem", role: .destructive) { deletePending() }
        } message: {
            Text("The poem is removed from your library. Its Moment stays marked as saved.")
        }
    }

    private func deletePending() {
        guard let poem = pendingDelete else { return }
        pendingDelete = nil
        context.delete(poem)
        do {
            try context.save()
            errorText = nil
        } catch {
            context.rollback()
            errorText = "Could not delete: \(error.localizedDescription)"
        }
    }
}

private struct PoemRow: View {
    let poem: Poem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(poem.displayTitle).font(.headline).lineLimit(1)
            HStack {
                if let poet = poem.poet { Text(poet) }
                Spacer()
                Text(poem.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.subheadline).foregroundStyle(.secondary)
            let preview = poem.title == nil ? poem.firstLines(3).split(separator: " / ").dropFirst()
                .joined(separator: " / ") : poem.firstLines(2)
            if !preview.isEmpty {
                Text(preview).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let environment = AppEnvironment()
    LibraryView()
        .modelContainer(environment.library.container)
}
