import AnamnesisKit
import SwiftData
import SwiftUI
import UIKit

/// Saved transcripts (spec 012, PRD M6; spec 015 R4; spec 016 R3/R7; spec 020): one compact card each (title,
/// speaker, one line), search as you type, sort and speaker chips. A card opens its transcript with a zoom. **+**
/// writes one by hand (spec 020 R9). Stored as `Poem`; the field `poet` is shown as *Speaker*.
struct LibraryView: View {
    /// Switches to the Transcribe tab from the empty state.
    var startListening: () -> Void = {}
    @Environment(AppEnvironment.self) private var environment
    @State private var filter = LibraryFilter()
    @State private var path: [Poem] = []
    /// All transcripts, for the filter menus and the "nothing yet" state.
    @Query private var allPoems: [Poem]
    @Namespace private var zoom
    /// A hand-written transcript being composed; it reaches the store only when saved.
    @State private var composing: Poem?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if allPoems.isEmpty {
                    EmptyLibraryView(startListening: startListening) { composing = Poem(body: "") }
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
            .searchable(text: $filter.searchText, prompt: "Words, titles, speakers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New transcript", systemImage: "square.and.pencil") { composing = Poem(body: "") }
                }
            }
            .sheet(item: $composing) { PoemEditorView(newPoem: $0) }
        }
        // *Delete all data* removed every transcript, including one left open here; drop it from the stack so
        // returning to this tab never shows (or touches) a deleted model.
        .onChange(of: environment.dataDeletedAt) { path.removeAll() }
        #if DEBUG
        // SPIKE: App Store screenshots; acts once the seeded transcripts arrive.
        .onChange(of: allPoems.count, initial: true) {
            guard ScreenshotScene.current?.opensHero == true, path.isEmpty,
                  let hero = allPoems.first(where: { $0.title == ScreenshotScene.heroTitle }) else { return }
            path = [hero]
        }
        #endif
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
            Eyebrow(poems.count == 1 ? "1 transcript" : "\(poems.count) transcripts").cardRow()
            if let errorText { ErrorLine(errorText).cardRow() }
            ForEach(poems) { poem in
                Button { open(poem) } label: {
                    PoemCard(poem: poem)
                }
                .buttonStyle(CardButtonStyle())
                .matchedTransitionSource(id: poem.id, in: zoom)
                .accessibilityHint("Opens the transcript")
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
                    ContentUnavailableView("No matching transcripts",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Nothing by this speaker matches."))
                } else {
                    ContentUnavailableView.search(text: filter.query)
                }
            }
        }
        .confirmationDialog("Delete this transcript?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete transcript", role: .destructive) { deletePending() }
        } message: {
            Text("The transcript is removed from your library. This cannot be undone.")
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

/// Sort and speaker as chips that open menus; a filled chip is an active filter.
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
                        Label("Speaker", systemImage: "person").tag(LibrarySort.poet)
                    }
                } label: {
                    chip(sortName, systemImage: "arrow.up.arrow.down", active: false)
                }
                if !poets.isEmpty {
                    Menu {
                        Picker("Speaker", selection: $filter.poet) {
                            Text("All speakers").tag(String?.none)
                            ForEach(poets, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    } label: {
                        chip(filter.poet ?? "Speaker", systemImage: "person", active: filter.poet != nil)
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
        case .poet: "Speaker A–Z"
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

/// A transcript in the library (spec 016 R7): title, speaker, and one line of it, nothing else.
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

    /// One line of the transcript that is not already the title: the first, or the second when the first is the title.
    /// Reads only as far into the body as it needs.
    private var line: String? {
        let title = poem.displayTitle
        return poem.nonEmptyLines.first { $0 != title }
    }
}

private struct EmptyLibraryView: View {
    let startListening: () -> Void
    let write: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Your transcripts will live here").font(Theme.display(.title2))
            } icon: {
                Image(systemName: "book.closed").foregroundStyle(Theme.ember)
            }
        } description: {
            Text("Transcribe your media and everything said lands here, ready to read, edit and share.")
        } actions: {
            Button("Start transcribing", systemImage: "waveform", action: startListening)
                .buttonStyle(ProminentButtonStyle())
            Button("Write one", systemImage: "square.and.pencil", action: write)
                .buttonStyle(QuietButtonStyle())
        }
    }
}

#Preview {
    let environment = AppEnvironment()
    LibraryView()
        .environment(environment)
        .modelContainer(environment.library.container)
}
