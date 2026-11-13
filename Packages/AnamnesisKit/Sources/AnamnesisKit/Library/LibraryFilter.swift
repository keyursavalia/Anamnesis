import Foundation
import SwiftData

public enum LibrarySort: String, Sendable, CaseIterable {
    case newest, title, poet
}

/// What the Library shows (spec 012 R1–R3). Search and poet run in the store predicate; the tag filter and the
/// sorts run in memory, because `tags.contains` in a predicate crashes SwiftData (F-047) and the title sort uses
/// the first line when there is no title.
public struct LibraryFilter: Sendable, Equatable {
    public var searchText: String
    public var tag: String?
    public var poet: String?
    public var sort: LibrarySort

    public init(searchText: String = "", tag: String? = nil, poet: String? = nil, sort: LibrarySort = .newest) {
        self.searchText = searchText
        self.tag = tag
        self.poet = poet
        self.sort = sort
    }

    public var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isFiltering: Bool { !query.isEmpty || tag != nil || poet != nil }

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

    /// The tag filter and the sort, on the poems the predicate returned.
    public func refine(_ poems: [Poem]) -> [Poem] {
        let tagged = tag.map { tag in
            poems.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        } ?? poems
        return tagged.sorted { lhs, rhs in
            switch sort {
            case .newest:
                return lhs.createdAt > rhs.createdAt
            case .title:
                let order = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
                return order == .orderedSame ? lhs.createdAt > rhs.createdAt : order == .orderedAscending
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

    /// Distinct tags for the filter menu, first spelling kept, sorted.
    public static func tags(in poems: [Poem]) -> [String] {
        PoemTags.parse(PoemTags.format(poems.flatMap(\.tags)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(count)
            .joined(separator: " / ")
    }
}
