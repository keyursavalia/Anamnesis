import Foundation
import SwiftData

/// Keeping a Moment as a poem (spec 010; automatic since spec 016 R1). The caller saves the context.
extension MomentRecord {
    /// Keeps the Moment as a poem with its D-024 line breaks. A Moment already saved returns its poem, so a second
    /// call never makes two. Works from `new` and `dismissed` (Moments dismissed before spec 016).
    @discardableResult
    public func saveAsPoem(in context: ModelContext, now: Date = Date()) -> Poem {
        if let poem { return poem }
        let poem = Poem(body: poemText, createdAt: now, sourceSessionID: session?.spoolSessionID)
        context.insert(poem)
        self.poem = poem
        review = .saved
        return poem
    }
}

extension CaptureSession {
    /// Poems that came from this capture and are still in the library.
    public var keptPoemCount: Int { moments.count { $0.poem != nil } }
}
