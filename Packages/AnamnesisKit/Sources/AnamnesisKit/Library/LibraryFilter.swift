import Foundation
import SwiftData

public enum LibrarySort: String, Sendable, CaseIterable {
    case newest, title, poet
}

/// What the Library shows (spec 012 R1–R3; spec 016 R3 removed tags). Search and poet run in the store
/// predicate; the sorts run in memory, because the title sort uses the first line when there is no title.
public struct LibraryFilter: Sendable, Equatable {
    public var searchText: String
    public var poet: String?
    public var sort: LibrarySort

    public init(searchText: String = "", poet: String? = nil, sort: LibrarySort = .newest) {
        self.searchText = searchText
        self.poet = poet
        self.sort = sort
    }

    public var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Body, title and poet, case- and diacritic-insensitive (R2), and the poet filter (R3).
    public var predicate: Predicate<Poem> {
        let query = query
        let anyText = query.isEmpty
        let poet = poet ?? ""
        let anyPoet = self.poet == nil
        return #Predicate<Poem> { poem in
            (anyPoet || poem.poet == poet)
                && (anyText || poem.body.localizedStandardContains(query)
                    || (poem.title?.localizedStandardContains(query) ?? false)
                    || (poem.poet?.localizedStandardContains(query) ?? false))
        }
    }

    /// The sort, on the poems the predicate returned.
    public func refine(_ poems: [Poem]) -> [Poem] {
        if sort == .title {
            // Each title once, not once per comparison: an untitled poem's title is read from its body.
            return poems.map { (poem: $0, title: $0.displayTitle) }
                .sorted { lhs, rhs in
                    let order = lhs.title.localizedStandardCompare(rhs.title)
                    return order == .orderedSame ? lhs.poem.createdAt > rhs.poem.createdAt : order == .orderedAscending
                }
                .map(\.poem)
        }
        return poems.sorted { lhs, rhs in
            switch sort {
            case .newest, .title:
                return lhs.createdAt > rhs.createdAt
            case .poet:
                switch (lhs.poet, rhs.poet) {
                case let (left?, right?) where left.localizedStandardCompare(right) != .orderedSame:
                    return left.localizedStandardCompare(right) == .orderedAscending
                case (nil, _?): return false
                case (_?, nil): return true
                default: return lhs.createdAt > rhs.createdAt
                }
            }
        }
    }

    public static func poets(in poems: [Poem]) -> [String] {
        Set(poems.compactMap(\.poet)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

extension Poem {
    /// The title, else the first non-empty line (spec 011 R3, spec 012 R1).
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return firstLines(1)
    }

    /// The first `count` non-empty lines, joined by " / ".
    public func firstLines(_ count: Int) -> String {
        nonEmptyLines.prefix(count).joined(separator: " / ")
    }

    /// The body's non-empty lines, trimmed, read one at a time: a caller that needs the first few stops there
    /// instead of splitting a long transcript whole.
    public var nonEmptyLines: UnfoldSequence<String, Substring> {
        sequence(state: body[...]) { rest in
            while !rest.isEmpty {
                let end = rest.firstIndex(where: \.isNewline) ?? rest.endIndex
                let line = rest[..<end].trimmingCharacters(in: .whitespaces)
                rest = end == rest.endIndex ? rest[end...] : rest[rest.index(after: end)...]
                if !line.isEmpty { return line }
            }
            return nil
        }
    }
}
