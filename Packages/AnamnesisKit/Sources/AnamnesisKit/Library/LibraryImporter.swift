import Foundation
import SwiftData

/// One Moment of a `SessionTranscript`, as plain values ready for the store (spec 009 R2).
public struct MomentDraft: Sendable, Equatable {
    public var index: Int
    public var startSec: Double
    public var endSec: Double
    public var text: String
    public var poemText: String
    public var meanConfidence: Double?
    public var flags: [HallucinationFlag]
    public var segmentsData: Data

    public static func drafts(from transcript: SessionTranscript) throws -> [MomentDraft] {
        var flagsBySegment: [String: [HallucinationFlag]] = [:]
        for flagged in transcript.transcript.segments {
            flagsBySegment[key(flagged.segment), default: []] += flagged.flags
        }
        return try transcript.moments.enumerated().map { index, moment in
            let confidences = moment.segments.compactMap(\.confidence)
            let flags = Set(moment.segments.flatMap { flagsBySegment[key($0)] ?? [] })
            return MomentDraft(
                index: index, startSec: moment.startSec, endSec: moment.endSec, text: moment.text,
                poemText: LineBreaker.format(moment.segments),
                meanConfidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count),
                flags: flags.sorted { $0.rawValue < $1.rawValue },
                segmentsData: try SessionFileCodec.encode(moment.segments))
        }
    }

    /// Moments hold plain segments; their flags live on the transcript's flagged copies.
    private static func key(_ segment: TranscriptSegment) -> String { "\(segment.startSec)|\(segment.text)" }
}

/// What the app knows about a spool session from its folder (manifest, `capture.json`).
public struct SessionSnapshot: Sendable, Equatable {
    public var spoolSessionID: String
    public var startedAt: Date
    public var stoppedAt: Date?
    public var durationSec: Double
    public var stopReason: String?
    public var hasAudio: Bool

    public init(spoolSessionID: String, startedAt: Date, stoppedAt: Date? = nil, durationSec: Double,
                stopReason: String? = nil, hasAudio: Bool) {
        self.spoolSessionID = spoolSessionID
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.durationSec = durationSec
        self.stopReason = stopReason
        self.hasAudio = hasAudio
    }
}

/// Writes the spool's sessions and transcripts into the library store, off the main actor (spec 009 R2–R4).
/// Every call saves once, so a process killed mid-call leaves the store as it was.
/// Never relies on `#Unique` upsert: it merges to-many relationships (old Moments plus new ones, F-043).
@ModelActor
public actor LibraryImporter {
    public enum Outcome: Sendable, Equatable {
        case imported(moments: Int)
        /// The same transcript version was imported before.
        case alreadyImported
        /// A Moment was already reviewed: Moments kept, metrics and state updated.
        case keptReviewedMoments
    }

    /// Adds sessions seen in the spool for the first time and refreshes audio and duration. Never deletes a row
    /// whose folder is gone: the transcript lives in the store. Returns the number of sessions inserted.
    @discardableResult
    public func sync(_ snapshots: [SessionSnapshot]) throws -> Int {
        var inserted = 0
        for snapshot in snapshots {
            let session: CaptureSession
            if let existing = try fetch(snapshot.spoolSessionID) {
                session = existing
            } else {
                session = CaptureSession(spoolSessionID: snapshot.spoolSessionID, startedAt: snapshot.startedAt,
                                         durationSec: snapshot.durationSec)
                modelContext.insert(session)
                inserted += 1
            }
            // A manifest without segments reads 0 s; keep a duration the transcript already gave.
            if snapshot.durationSec > 0 { session.durationSec = snapshot.durationSec }
            session.stoppedAt = snapshot.stoppedAt ?? session.stoppedAt
            session.stopReason = snapshot.stopReason ?? session.stopReason
            session.audioDeleted = !snapshot.hasAudio
        }
        if modelContext.hasChanges { try modelContext.save() }
        return inserted
    }

    public func importTranscript(_ transcript: SessionTranscript, audioDeleted: Bool) throws -> Outcome {
        let session: CaptureSession
        if let existing = try fetch(transcript.sessionID) {
            session = existing
        } else {
            let capture = transcript.metrics.capture
            session = CaptureSession(spoolSessionID: transcript.sessionID,
                                     startedAt: capture?.startedAt ?? transcript.transcript.createdAt,
                                     durationSec: transcript.metrics.audioSec)
            modelContext.insert(session)
        }
        if session.importedAt != nil, session.transcriptVersion == transcript.version {
            return .alreadyImported
        }
        let reviewed = session.moments.contains { $0.review != .new }
        if !reviewed {
            for moment in session.moments { modelContext.delete(moment) }
            for draft in try MomentDraft.drafts(from: transcript) {
                let moment = MomentRecord(draft)
                modelContext.insert(moment)
                moment.session = session
            }
        }
        session.state = .transcribed
        session.failureText = nil
        session.transcriptVersion = transcript.version
        session.importedAt = Date()
        session.metricsData = try SessionFileCodec.encode(transcript.metrics)
        session.stoppedAt = transcript.metrics.capture?.stoppedAt ?? session.stoppedAt
        session.stopReason = transcript.metrics.capture?.stopReason ?? session.stopReason
        session.audioDeleted = audioDeleted
        if session.durationSec <= 0 { session.durationSec = transcript.metrics.audioSec }
        try modelContext.save()
        return reviewed ? .keptReviewedMoments : .imported(moments: transcript.moments.count)
    }

    public func recordFailure(sessionID: String, text: String) throws {
        guard let session = try fetch(sessionID), session.state != .transcribed else { return }
        session.state = .failed
        session.failureText = text
        session.attempts += 1
        try modelContext.save()
    }

    /// Manual Retry: back to `saved`, attempts kept for the log.
    public func clearFailure(sessionID: String) throws {
        guard let session = try fetch(sessionID), session.state == .failed else { return }
        session.state = .saved
        session.failureText = nil
        try modelContext.save()
    }

    /// Removes the session and its Moments; poems saved from it stay, with `moment` cleared.
    public func delete(sessionID: String) throws {
        guard let session = try fetch(sessionID) else { return }
        modelContext.delete(session)
        try modelContext.save()
    }

    /// Sessions the queue may start: `saved`, or `failed` with fewer than `maxAttempts` attempts. Oldest first.
    public func transcribableSessionIDs(maxAttempts: Int) throws -> [String] {
        let saved = StoredSessionState.saved.rawValue
        let failed = StoredSessionState.failed.rawValue
        let descriptor = FetchDescriptor<CaptureSession>(
            predicate: #Predicate { $0.stateRaw == saved || ($0.stateRaw == failed && $0.attempts < maxAttempts) },
            sortBy: [SortDescriptor(\.startedAt)])
        return try modelContext.fetch(descriptor).map(\.spoolSessionID)
    }

    /// Sessions whose transcript is in the store, at any version.
    public func importedSessionIDs() throws -> Set<String> {
        let descriptor = FetchDescriptor<CaptureSession>(predicate: #Predicate { $0.importedAt != nil })
        return Set(try modelContext.fetch(descriptor).map(\.spoolSessionID))
    }

    private func fetch(_ id: String) throws -> CaptureSession? {
        var descriptor = FetchDescriptor<CaptureSession>(predicate: #Predicate { $0.spoolSessionID == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
