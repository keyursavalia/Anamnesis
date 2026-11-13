import AnamnesisKit
import SwiftData
import SwiftUI

/// Fix and annotate a saved poem (spec 011, PRD M5). Presented as a sheet; unsaved changes ask before closing.
struct PoemEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PoemEditorModel
    @State private var confirmingClose = false
    @State private var errorText: String?

    init(poem: Poem) {
        _model = State(initialValue: PoemEditorModel(poem: poem))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $model.text, selection: $model.selection)
                        .frame(minHeight: 280)
                        .accessibilityLabel("Poem text")
                } header: {
                    Text("Poem")
                } footer: {
                    Text("Orange words were unsure in the transcript; they turn normal once you change them. "
                         + "Put the cursor between two poems and tap Split here to make two.")
                }
                Section("Details") {
                    TextField("Title (the first line is used when empty)", text: $model.draft.title)
                    TextField("Poet", text: $model.draft.poet)
                        .textContentType(.name)
                    TextField("Source, e.g. Instagram reel", text: $model.draft.sourceNote)
                    TextField("Tags, comma-separated", text: $model.draft.tagsText)
                        .textInputAutocapitalization(.never)
                }
                if let errorText {
                    Text(errorText).font(.callout).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit poem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .onChange(of: model.text) { model.textDidChange() }
            .onChange(of: model.draft) { model.draftDidChange() }
            .confirmationDialog("Save your changes?", isPresented: $confirmingClose, titleVisibility: .visible) {
                Button("Save") { saveAndClose() }
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(model.isDirty)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if model.isDirty { confirmingClose = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { saveAndClose() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.history.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }
                .disabled(!model.history.canRedo)
            Spacer()
            Button("Split here", systemImage: "scissors") { split() }
                .disabled(!model.canSplit)
        }
    }

    private func saveAndClose() {
        do {
            try model.save(in: context)
            dismiss()
        } catch {
            context.rollback()
            errorText = "Could not save: \(error.localizedDescription)"
        }
    }

    private func split() {
        do {
            try model.split(in: context)
            errorText = nil
        } catch {
            context.rollback()
            errorText = "Could not split: \(error.localizedDescription)"
        }
    }
}
