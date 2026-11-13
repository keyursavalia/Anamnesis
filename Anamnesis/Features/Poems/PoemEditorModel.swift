import AnamnesisKit
import Foundation
import Observation
import SwiftData
import SwiftUI

/// The editor's state for one poem (spec 011): a draft, the styled body for the rich `TextEditor`, the cursor,
/// and undo/redo snapshots. Nothing reaches the store until `save` or `split`.
@Observable
final class PoemEditorModel {
    private(set) var poem: Poem
    /// What the store holds; `isDirty` compares the draft with it.
    private(set) var original: PoemDraft
    var draft: PoemDraft
    /// The body as the editor shows it: plain characters plus the unsure-word highlight.
    var text: AttributedString
    var selection = AttributedTextSelection()
    private(set) var history: EditHistory<PoemDraft>
    /// The Moment's tokens; empty for a poem split off from another (no Moment, nothing to highlight).
    @ObservationIgnored private var words: [TranscriptWord] = []

    init(poem: Poem) {
        self.poem = poem
        let draft = PoemDraft(poem: poem)
        original = draft
        self.draft = draft
        text = AttributedString(draft.body)
        history = EditHistory(draft)
        load(poem)
    }

    var isDirty: Bool { draft != original }

    // MARK: - Changes

    /// The editor changed `text`: take its characters as the body, then re-highlight (R2).
    func textDidChange() {
        let body = String(text.characters)
        if body != draft.body { draft.body = body }
        restyle()
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
        guard let other = poem.splitOff(at: offset, in: context) else { return }
        try context.save()
        load(other)
    }

    // MARK: - Private

    private func load(_ poem: Poem) {
        self.poem = poem
        words = UnsureWords.words(of: poem.moment?.segments ?? [])
        original = PoemDraft(poem: poem)
        history = EditHistory(original)
        show(original)
    }

    private func show(_ value: PoemDraft) {
        draft = value
        text = AttributedString(value.body)
        selection = AttributedTextSelection()
        restyle()
    }

    /// Recolours the whole body in place. Only attributes change, so `transform` keeps the cursor where it was.
    private func restyle() {
        let ranges = UnsureWords.ranges(in: draft.body, words: words)
        var styled = text
        var styledSelection = selection
        styled.transform(updating: &styledSelection) { body in
            body.foregroundColor = nil
            body.underlineStyle = nil
            for range in ranges {
                let lower = body.characters.index(body.startIndex, offsetBy: range.lowerBound)
                let upper = body.characters.index(lower, offsetBy: range.count)
                body[lower..<upper].foregroundColor = .orange
                body[lower..<upper].underlineStyle = .single
            }
        }
        guard styled != text else { return }
        text = styled
        selection = styledSelection
    }
}
