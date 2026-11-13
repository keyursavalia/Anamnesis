import AnamnesisKit
import SwiftData
import SwiftUI
import UIKit

/// Read one poem (spec 012 R4): the text with its line breaks, details, Edit (spec 011), Copy, Delete.
struct PoemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let poem: Poem
    @Query private var sources: [CaptureSession]
    @State private var editing: Poem?
    @State private var confirmingDelete = false
    @State private var errorText: String?

    init(poem: Poem) {
        self.poem = poem
        let sessionID = poem.sourceSessionID ?? ""
        _sources = Query(filter: #Predicate<CaptureSession> { $0.spoolSessionID == sessionID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(poem.displayTitle).font(.title2.weight(.semibold))
                    if let poet = poem.poet { Text(poet).font(.headline).foregroundStyle(.secondary) }
                }
                Text(poem.body)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                details
                if let errorText {
                    Text(errorText).font(.callout).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                shareMenu
                Button("Edit", systemImage: "pencil") { editing = poem }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .sheet(item: $editing) { PoemEditorView(poem: $0) }
        .confirmationDialog("Delete this poem?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete poem", role: .destructive) { delete() }
        } message: {
            Text("The poem is removed from your library. Its Moment stays marked as saved.")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !poem.tags.isEmpty {
                HStack {
                    ForEach(poem.tags, id: \.self) { tag in
                        Text(tag).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tags: " + poem.tags.joined(separator: ", "))
            }
            if let note = poem.sourceNote { Label(note, systemImage: "link") }
            if let session = sources.first {
                Label("From a capture on " + session.startedAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "waveform")
            }
            Label("Saved " + poem.createdAt.formatted(date: .abbreviated, time: .shortened)
                  + (poem.userEdited ? " · edited " + poem.updatedAt.formatted(date: .abbreviated, time: .shortened)
                                     : ""),
                  systemImage: "calendar")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// Copy and share (spec 014 R1): plain text with title, poet, source and tags; or a Markdown file.
    private var shareMenu: some View {
        let export = PoemExport(poem: poem)
        return Menu("Share", systemImage: "square.and.arrow.up") {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = export.plainText }
            ShareLink("Share as text", item: export.plainText)
            ShareLink("Share as Markdown",
                      item: MarkdownFile(text: export.markdown, fileName: export.fileName),
                      preview: SharePreview(export.fileName))
        }
    }

    private func delete() {
        context.delete(poem)
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            errorText = "Could not delete: \(error.localizedDescription)"
        }
    }
}
