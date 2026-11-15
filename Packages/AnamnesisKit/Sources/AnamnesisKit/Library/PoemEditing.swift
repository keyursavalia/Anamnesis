import Foundation
import SwiftData

/// *Split here* (spec 011 R1): the text before and after the cursor, without the whitespace at the cut.
public enum PoemSplit {
    /// nil when either half would be empty.
    public static func split(_ body: String, at offset: Int) -> (first: String, second: String)? {
        let chars = Array(body)
        guard (0...chars.count).contains(offset) else { return nil }
        var end = offset
        while end > 0, chars[end - 1].isWhitespace { end -= 1 }
        var start = offset
        while start < chars.count, chars[start].isWhitespace { start += 1 }
        guard end > 0, start < chars.count else { return nil }
        return (String(chars[..<end]), String(chars[start...]))
    }
}

/// The editor's working copy of a poem (spec 011). Strings are never nil here; empty means unset.
public struct PoemDraft: Sendable, Equatable {
    public var body: String
    public var title: String
    public var poet: String
    /// Free text or a link to the reel (spec 016 R4).
    public var sourceNote: String

    public init(body: String = "", title: String = "", poet: String = "", sourceNote: String = "") {
        self.body = body
        self.title = title
        self.poet = poet
        self.sourceNote = sourceNote
    }

    public init(poem: Poem) {
        self.init(body: poem.body, title: poem.title ?? "", poet: poem.poet ?? "", sourceNote: poem.sourceNote ?? "")
    }

    /// Writes the draft back. `userEdited` is set once the body differs from the stored one (R2).
    public func apply(to poem: Poem, now: Date = Date()) {
        if body != poem.body {
            poem.body = body
            poem.userEdited = true
        }
        poem.title = Self.nonEmpty(title)
        poem.poet = Self.nonEmpty(poet)
        poem.sourceNote = Self.nonEmpty(sourceNote)
        poem.updatedAt = now
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Poem {
    /// Keeps the text before `offset` and returns a new poem with the rest (R1, AC2). The new poem has the same
    /// capture, poet and source, no title and no Moment (a Moment links to one poem). The caller saves.
    public func splitOff(at offset: Int, in context: ModelContext, now: Date = Date()) -> Poem? {
        guard let (first, second) = PoemSplit.split(body, at: offset) else { return nil }
        body = first
        userEdited = true
        updatedAt = now
        let other = Poem(body: second, createdAt: now, sourceSessionID: sourceSessionID)
        other.poet = poet
        other.sourceNote = sourceNote
        other.userEdited = true
        context.insert(other)
        return other
    }
}

/// Undo/redo snapshots of a whole value (spec 011 R4). Changes less than `coalesce` apart are one step.
public struct EditHistory<Value: Equatable & Sendable>: Sendable {
    public private(set) var current: Value
    private var undoStack: [Value] = []
    private var redoStack: [Value] = []
    private var lastRecordAt: Date?
    public let coalesce: TimeInterval
    public let limit: Int

    public init(_ initial: Value, coalesce: TimeInterval = 1, limit: Int = 200) {
        current = initial
        self.coalesce = coalesce
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func record(_ value: Value, at now: Date = Date()) {
        guard value != current else { return }
        let merges = lastRecordAt.map { now.timeIntervalSince($0) < coalesce } ?? false
        if !merges || undoStack.isEmpty {
            undoStack.append(current)
            if undoStack.count > limit { undoStack.removeFirst() }
        }
        current = value
        redoStack.removeAll()
        lastRecordAt = now
    }

    public mutating func undo() -> Value? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        current = previous
        lastRecordAt = nil
        return previous
    }

    public mutating func redo() -> Value? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        current = next
        lastRecordAt = nil
        return next
    }
}
