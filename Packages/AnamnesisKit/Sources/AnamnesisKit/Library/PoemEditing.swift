import Foundation
import SwiftData

/// Where the transcript's unsure words still are in a poem body (spec 011 R2). Recomputed from the current text on
/// every change, so a word stops being highlighted as soon as it is edited, with nothing stored.
public enum UnsureWords {
    /// Same bar as the Moment screen (spec 008).
    public static let threshold = 0.5
    /// How far past the previous match a word may be. Grows with each miss so the walk finds its place again
    /// after an inserted line.
    static let window = 40

    /// Character-offset ranges of the words below `threshold`. `words` are the Moment's tokens in the order
    /// `LineBreaker.format` joined them; each is matched as a whole word, forward from the previous match.
    public static func ranges(in body: String, words: [TranscriptWord],
                              below threshold: Double = threshold) -> [Range<Int>] {
        let chars = Array(body)
        var cursor = 0
        var misses = 0
        var result: [Range<Int>] = []
        for word in words {
            let token = Array(word.text)
            guard !token.isEmpty,
                  let start = find(token, in: chars, from: cursor, limit: cursor + window * (misses + 1)) else {
                misses += 1
                continue
            }
            misses = 0
            cursor = start + token.count
            if let confidence = word.confidence, confidence < threshold { result.append(start..<cursor) }
        }
        return result
    }

    /// The Moment's tokens in `LineBreaker.format(_: [TranscriptSegment])` order.
    public static func words(of segments: [TranscriptSegment]) -> [TranscriptWord] {
        segments.sorted { $0.startSec < $1.startSec }
            .flatMap { $0.timedTokens.sorted { $0.startSec < $1.startSec } }
    }

    private static func find(_ token: [Character], in chars: [Character], from: Int, limit: Int) -> Int? {
        let last = min(limit, chars.count - token.count)
        guard last >= from else { return nil }
        for index in from...last where chars[index..<index + token.count].elementsEqual(token)
            && isBoundary(chars, index - 1) && isBoundary(chars, index + token.count) {
            return index
        }
        return nil
    }

    private static func isBoundary(_ chars: [Character], _ index: Int) -> Bool {
        guard chars.indices.contains(index) else { return true }
        return !(chars[index].isLetter || chars[index].isNumber)
    }
}

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

/// Tags as typed: comma-separated, trimmed, duplicates (any case) dropped keeping the first spelling.
public enum PoemTags {
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    public static func format(_ tags: [String]) -> String { tags.joined(separator: ", ") }
}

/// The editor's working copy of a poem (spec 011). Strings are never nil here; empty means unset.
public struct PoemDraft: Sendable, Equatable {
    public var body: String
    public var title: String
    public var poet: String
    public var sourceNote: String
    public var tagsText: String

    public init(body: String = "", title: String = "", poet: String = "", sourceNote: String = "",
                tagsText: String = "") {
        self.body = body
        self.title = title
        self.poet = poet
        self.sourceNote = sourceNote
        self.tagsText = tagsText
    }

    public init(poem: Poem) {
        self.init(body: poem.body, title: poem.title ?? "", poet: poem.poet ?? "",
                  sourceNote: poem.sourceNote ?? "", tagsText: PoemTags.format(poem.tags))
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
        poem.tags = PoemTags.parse(tagsText)
        poem.updatedAt = now
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Poem {
    /// Keeps the text before `offset` and returns a new poem with the rest (R1, AC2). The new poem has the same
    /// source, poet, note and tags, no title and no Moment (a Moment links to one poem). The caller saves.
    public func splitOff(at offset: Int, in context: ModelContext, now: Date = Date()) -> Poem? {
        guard let (first, second) = PoemSplit.split(body, at: offset) else { return nil }
        body = first
        userEdited = true
        updatedAt = now
        let other = Poem(body: second, createdAt: now, sourceSessionID: sourceSessionID)
        other.poet = poet
        other.sourceNote = sourceNote
        other.tags = tags
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
