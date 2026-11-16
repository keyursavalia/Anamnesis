import AnamnesisKit
import SwiftData
import SwiftUI
import UIKit

/// Saved poems (spec 012, PRD M6; spec 015 R4; spec 016 R3/R7): one compact card per poem (title, poet, one line),
/// search as you type, sort and poet chips. A card opens its poem with a zoom.
struct LibraryView: View {
    /// Switches to the Listen tab from the empty state.
    var startListening: () -> Void = {}
    @State private var filter = LibraryFilter()
    @State private var path: [Poem] = []
    /// All poems, for the filter menus and the "no poems yet" state.
    @Query private var allPoems: [Poem]
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if allPoems.isEmpty {
                    EmptyLibraryView(startListening: startListening)
                } else {
                    // `filter` is passed by value on purpose: reading it here re-creates the list, and with it the
                    // store query, each time the search or a chip changes. A binding alone would keep the old query.
                    PoemListView(filter: filter, editFilter: $filter, allPoems: allPoems, zoom: zoom) {
                        path.append($0)
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Library")
            .navigationDestination(for: Poem.self) { poem in
                PoemDetailView(poem: poem)
                    .navigationTransition(.zoom(sourceID: poem.id, in: zoom))
            }
            .searchable(text: $filter.searchText, prompt: "Words, titles, poets")
        }
    }
}

/// The list for one filter. The store runs the search and poet predicate; sorting runs in memory.
private struct PoemListView: View {
    @Environment(\.modelContext) private var context
    let filter: LibraryFilter
    @Binding var editFilter: LibraryFilter
    let allPoems: [Poem]
    let zoom: Namespace.ID
    let open: (Poem) -> Void
    @Query private var matches: [Poem]
    @State private var pendingDelete: Poem?
    @State private var errorText: String?

    init(filter: LibraryFilter, editFilter: Binding<LibraryFilter>, allPoems: [Poem], zoom: Namespace.ID,
         open: @escaping (Poem) -> Void) {
        self.filter = filter
        _editFilter = editFilter
        self.allPoems = allPoems
        self.zoom = zoom
        self.open = open
        _matches = Query(filter: filter.predicate, sort: \Poem.createdAt, order: .reverse)
    }

    var body: some View {
        let poems = filter.refine(matches)
        List {
            LibraryFilterBar(filter: $editFilter, allPoems: allPoems)
                .frame(maxWidth: Theme.readingWidth)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            Eyebrow(poems.count == 1 ? "1 poem" : "\(poems.count) poems").cardRow()
            if let errorText { ErrorLine(errorText).cardRow() }
            ForEach(poems) { poem in
                Button { open(poem) } label: {
                    PoemCard(poem: poem)
                }
                .buttonStyle(CardButtonStyle())
                .matchedTransitionSource(id: poem.id, in: zoom)
                .accessibilityHint("Opens the poem")
                .cardRow()
                .swipeActions {
                    Button("Delete", systemImage: "trash") { pendingDelete = poem }.tint(Theme.danger)
                }
                .contextMenu {
                    let export = PoemExport(poem: poem)
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = export.plainText }
                    ShareLink("Share", item: export.plainText)
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = poem }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.smooth, value: poems.map(\.id))
        .overlay {
            if poems.isEmpty {
                if filter.query.isEmpty {
                    ContentUnavailableView("No matching poems", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("No poem by this poet matches."))
                } else {
                    ContentUnavailableView.search(text: filter.query)
                }
            }
        }
        .confirmationDialog("Delete this poem?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete poem", role: .destructive) { deletePending() }
        } message: {
            Text("The poem is removed from your library. This cannot be undone.")
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

/// Sort and poet as chips that open menus; a filled chip is an active filter.
private struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    let allPoems: [Poem]

    var body: some View {
        let poets = LibraryFilter.poets(in: allPoems)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $filter.sort) {
                        Label("Newest", systemImage: "clock").tag(LibrarySort.newest)
                        Label("Title", systemImage: "textformat").tag(LibrarySort.title)
                        Label("Poet", systemImage: "person").tag(LibrarySort.poet)
                    }
                } label: {
                    chip(sortName, systemImage: "arrow.up.arrow.down", active: false)
                }
                if !poets.isEmpty {
                    Menu {
                        Picker("Poet", selection: $filter.poet) {
                            Text("All poets").tag(String?.none)
                            ForEach(poets, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    } label: {
                        chip(filter.poet ?? "Poet", systemImage: "person", active: filter.poet != nil)
                    }
                }
                if filter.poet != nil {
                    Button("Clear") { withAnimation(.smooth) { filter.poet = nil } }
                        .font(.subheadline.weight(.semibold))
                        .tint(Theme.ember)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
    }

    private var sortName: String {
        switch filter.sort {
        case .newest: "Newest"
        case .title: "Title"
        case .poet: "Poet A–Z"
        }
    }

    private func chip(_ text: String, systemImage: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").imageScale(.small).font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(active ? Color.white : Theme.ink)
        .background(active ? AnyShapeStyle(Theme.emberFill) : AnyShapeStyle(Theme.sunken), in: .capsule)
    }
}

/// A poem in the library (spec 016 R7): title, poet, and one line of the poem, nothing else.
private struct PoemCard: View {
    let poem: Poem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(poem.displayTitle)
                .font(Theme.display(.title3))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            if let poet = poem.poet {
                Text(poet).font(Theme.verse(.subheadline)).italic().foregroundStyle(Theme.ember)
            }
            if let line {
                Text(line)
                    .font(Theme.verse(.callout))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .card()
        .contentShape(.rect(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    /// One line of the poem that is not already the title: the first, or the second when the first is the title.
    private var line: String? {
        let lines = poem.body.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.first { $0 != poem.displayTitle }
    }
}

private struct EmptyLibraryView: View {
    let startListening: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Your poems will live here").font(Theme.display(.title2))
            } icon: {
                Image(systemName: "book.closed").foregroundStyle(Theme.ember)
            }
        } description: {
            Text("Transcribe a reel and every poem you hear lands here, ready to read, edit and share.")
        } actions: {
            Button("Start listening", systemImage: "waveform", action: startListening)
                .buttonStyle(ProminentButtonStyle())
        }
    }
}

#Preview {
    let environment = AppEnvironment()
    LibraryView()
        .modelContainer(environment.library.container)
}
