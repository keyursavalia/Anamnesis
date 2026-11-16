import AnamnesisKit
import SwiftData
import SwiftUI

/// Fix and annotate a transcript (spec 011, PRD M5; restyled in spec 015 R6, simplified in spec 016: no tags, no
/// unsure-word hint, Source takes a link), or write one by hand from the Library (spec 020 R9): the same form, saved
/// only when the user taps Save. Presented as a sheet; unsaved changes ask before closing.
struct PoemEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PoemEditorModel
    @State private var confirmingClose = false
    @State private var errorText: String?
    @State private var savedCount = 0

    init(poem: Poem) {
        _model = State(initialValue: PoemEditorModel(poem: poem))
    }

    /// A transcript not in the store yet; Save inserts it, Cancel leaves nothing behind.
    init(newPoem: Poem) {
        _model = State(initialValue: PoemEditorModel(poem: newPoem, isNew: true))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $model.text, selection: $model.selection)
                        .font(Theme.verse(.title3))
                        .lineSpacing(5)
                        .frame(minHeight: 300)
                        .accessibilityLabel("Transcript text")
                } header: {
                    Eyebrow("Transcript")
                }
                .listRowBackground(Theme.surface)
                Section {
                    field("Title", prompt: "The first line, if left empty", text: $model.draft.title)
                    field("Speaker", prompt: "Who said it", text: $model.draft.poet)
                        .textContentType(.name)
                    sourceField
                } header: {
                    Eyebrow("Details")
                } footer: {
                    Text("Paste the link to where you heard it, to open it again later in whichever app it came from.")
                        .font(.footnote)
                }
                .listRowBackground(Theme.surface)
                if let errorText { ErrorLine(errorText).listRowBackground(Color.clear) }
            }
            .paperBackground()
            .navigationTitle(model.isNew ? "New transcript" : "Edit transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .tint(Theme.ember)
            .onChange(of: model.text) { model.textDidChange() }
            .onChange(of: model.draft) { model.draftDidChange() }
            .sensoryFeedback(.success, trigger: savedCount)
            .confirmationDialog("Save your changes?", isPresented: $confirmingClose, titleVisibility: .visible) {
                if model.canSave { Button("Save") { saveAndClose() } }
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(model.isDirty)
    }

    /// A link (or a note). Paste fills it straight from the clipboard; the system asks no permission for PasteButton.
    private var sourceField: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField("Source", text: $model.draft.sourceNote, prompt: Text("Link to the media"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if model.draft.sourceNote.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                        model.draft.sourceNote = text
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Theme.ember)
                }
            }
        } label: {
            Text("Source").foregroundStyle(Theme.inkSecondary)
        }
    }

    private func field(_ title: String, prompt: String, text: Binding<String>) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title).foregroundStyle(Theme.inkSecondary)
        }
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
                .fontWeight(.semibold)
                .disabled(!model.canSave)
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
            savedCount += 1
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
