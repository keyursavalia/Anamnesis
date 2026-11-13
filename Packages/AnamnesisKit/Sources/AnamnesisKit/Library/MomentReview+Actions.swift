import Foundation
import SwiftData

/// The review decisions on a Moment (spec 010). The caller saves the context.
extension MomentRecord {
    /// Keeps the Moment as a poem with its D-024 line breaks. A Moment already saved returns its poem, so a double
    /// tap never makes two. Works from `new` and `dismissed`.
    @discardableResult
    public func saveAsPoem(in context: ModelContext, now: Date = Date()) -> Poem {
        if let poem { return poem }
        let poem = Poem(body: poemText, createdAt: now, sourceSessionID: session?.spoolSessionID)
        context.insert(poem)
        self.poem = poem
        review = .saved
        return poem
    }

    /// `new` → `dismissed`. A saved Moment keeps its poem; removing poems belongs to the library (spec 012).
    public func dismiss() {
        guard review == .new else { return }
        review = .dismissed
    }

    /// `dismissed` → `new`.
    public func restore() {
        guard review == .dismissed else { return }
        review = .new
    }
}

extension CaptureSession {
    /// Moments still waiting for a decision.
    public var newMomentCount: Int { moments.count { $0.review == .new } }
    public var reviewedMomentCount: Int { moments.count - newMomentCount }
}
