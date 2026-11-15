import AnamnesisKit
import SwiftData
import SwiftUI
import UIKit

/// Read one poem (spec 012 R4; restyled in spec 015 R5; spec 016 R4–R6): set like a page, in New York at a reading
/// measure. The source opens the original reel when it is a link. Edit (spec 011), Copy and *Share card* in the
/// toolbar; Delete under More.
struct PoemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let poem: Poem
    @State private var editing: Poem?
    @State private var sharingCard = false
    @State private var confirmingDelete = false
    @State private var errorText: String?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heading
                Text(poem.body)
                    .font(Theme.verse(.title3))
                    .lineSpacing(8)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let note = poem.sourceNote { SourceView(note: note) }
                if let errorText { ErrorLine(errorText) }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 48)
            .frame(maxWidth: Theme.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { shareMenu }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { editing = poem }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Delete poem", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .sheet(item: $editing) { PoemEditorView(poem: $0) }
        .sheet(isPresented: $sharingCard) { ShareCardSheet(poem: PoemExport(poem: poem)) }
        .sensoryFeedback(.success, trigger: copied)
        .confirmationDialog("Delete this poem?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete poem", role: .destructive) { delete() }
        } message: {
            Text("The poem is removed from your library. This cannot be undone.")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(poem.displayTitle)
                .font(Theme.display(.largeTitle))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let poet = poem.poet {
                Text(poet).font(Theme.verse(.title3)).italic().foregroundStyle(Theme.ember)
            }
            Fleuron().padding(.top, 6)
        }
    }

    /// Copy (plain text with title, poet and source) and the share card (spec 016 R6).
    private var shareMenu: some View {
        Menu("Share", systemImage: "square.and.arrow.up") {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = PoemExport(poem: poem).plainText
                copied.toggle()
            }
            Button("Share card", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                sharingCard = true
            }
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

/// The poem's source (spec 016 R4). A link becomes a button that opens the original: the system routes it to the
/// app that owns it (Instagram, TikTok, …) or to Safari. Plain text stays plain text.
private struct SourceView: View {
    let note: String

    var body: some View {
        if let url = SourceLink.url(in: note) {
            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.ember)
                        .frame(width: 40, height: 40)
                        .background(Theme.ember.opacity(0.12), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open in \(SourceLink.name(of: url))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(14)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 0.5) }
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityHint("Opens the original reel")
            .contextMenu {
                Button("Copy link", systemImage: "link") { UIPasteboard.general.url = url }
            }
        } else {
            Label(note, systemImage: "link")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}
