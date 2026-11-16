import AnamnesisKit
import Foundation
import Observation
import SwiftData
import SwiftUI

/// The editor's state for one transcript (spec 011): a draft, the body for the rich `TextEditor` (needed for the
/// cursor that *Split here* uses), and undo/redo snapshots. Nothing reaches the store until `save` or `split`. A
/// hand-written one (spec 020 R9) starts outside the store and is inserted on its first save or split, so Cancel
/// leaves nothing behind.
@Observable
final class PoemEditorModel {
    private(set) var poem: Poem
    /// What the store holds; `isDirty` compares the draft with it.
    private(set) var original: PoemDraft
    var draft: PoemDraft
    /// The body as the editor shows it; plain characters since spec 016 (no unsure-word highlight).
    var text: AttributedString
    var selection = AttributedTextSelection()
    private(set) var history: EditHistory<PoemDraft>
    /// Not in the store yet (a hand-written transcript before its first save).
    private(set) var isNew: Bool

    init(poem: Poem, isNew: Bool = false) {
        self.poem = poem
        self.isNew = isNew
        let draft = PoemDraft(poem: poem)
        original = draft
        self.draft = draft
        text = AttributedString(draft.body)
        history = EditHistory(draft)
        load(poem)
    }

    var isDirty: Bool { draft != original }

    /// A new transcript needs some text before it can be saved; an existing one can always be saved.
    var canSave: Bool { !isNew || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Changes

    /// The editor changed `text`: take its characters as the body.
    func textDidChange() {
        let body = String(text.characters)
        if body != draft.body { draft.body = body }
    }

    /// Any field changed: one undo step per burst of typing (R4).
    func draftDidChange() { history.record(draft) }

    func undo() {
        guard let previous = history.undo() else { return }
        show(previous)
    }

    func redo() {
        guard let next = history.redo() else { return }
        show(next)
    }

    // MARK: - Store

    func save(in context: ModelContext) throws {
        draft.apply(to: poem)
        insertIfNew(in: context)
        try context.save()
        original = PoemDraft(poem: poem)
        draft = original
        history.record(draft)
    }

    /// The cursor as a character offset, when it is a single insertion point.
    var cursorOffset: Int? {
        guard case .insertionPoint(let index) = selection.indices(in: text) else { return nil }
        return text.characters.distance(from: text.startIndex, to: index)
    }

    var canSplit: Bool { cursorOffset.flatMap { PoemSplit.split(draft.body, at: $0) } != nil }

    /// *Split here* (R1): saves this poem with the text before the cursor and continues with the new one.
    func split(in context: ModelContext) throws {
        guard let offset = cursorOffset else { return }
        draft.apply(to: poem)
        insertIfNew(in: context)
        guard let other = poem.splitOff(at: offset, in: context) else { return }
        try context.save()
        load(other)
    }

    // MARK: - Private

    private func insertIfNew(in context: ModelContext) {
        guard isNew else { return }
        context.insert(poem)
        isNew = false
    }

    private func load(_ poem: Poem) {
        self.poem = poem
        original = PoemDraft(poem: poem)
        history = EditHistory(original)
        show(original)
    }

    private func show(_ value: PoemDraft) {
        draft = value
        text = AttributedString(value.body)
        selection = AttributedTextSelection()
    }
}
