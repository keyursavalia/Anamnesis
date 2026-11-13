import Foundation
import SwiftData

/// The library store, schema v1 (spec 009 R1, ARCHITECTURE §6). Host app only: the widget extension links this
/// package but never opens a store. Enums are stored as raw strings so predicates can filter on them.
public enum LibrarySchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [CaptureSession.self, MomentRecord.self, Poem.self] }

    /// One spool session (a capture), from its first sighting until the user deletes it.
    @Model
    public final class CaptureSession {
        #Unique<CaptureSession>([\.spoolSessionID])

        public var spoolSessionID: String
        public var startedAt: Date
        public var stoppedAt: Date?
        public var durationSec: Double
        /// `ProbeReport.StopReason` raw value from `capture.json`.
        public var stopReason: String?
        /// `StoredSessionState` raw value. Capturing and transcribing are live states, not stored.
        public var stateRaw: String
        public var failureText: String?
        /// Failed transcription attempts; later launches retry automatically below a limit.
        public var attempts: Int
        /// D-010 has removed the audio (or it was never there).
        public var audioDeleted: Bool
        public var transcriptVersion: Int?
        public var importedAt: Date?
        /// `SessionMetrics` as JSON (G5 timings, battery, thermal).
        public var metricsData: Data?
        @Relationship(deleteRule: .cascade, inverse: \MomentRecord.session)
        public var moments: [MomentRecord] = []

        public init(spoolSessionID: String, startedAt: Date, durationSec: Double) {
            self.spoolSessionID = spoolSessionID
            self.startedAt = startedAt
            self.durationSec = durationSec
            stateRaw = StoredSessionState.saved.rawValue
            attempts = 0
            audioDeleted = false
        }

        public var state: StoredSessionState {
            get { StoredSessionState(rawValue: stateRaw) ?? .saved }
            set { stateRaw = newValue.rawValue }
        }

        public var metrics: SessionMetrics? {
            metricsData.flatMap { try? SessionFileCodec.decoder.decode(SessionMetrics.self, from: $0) }
        }

        public var sortedMoments: [MomentRecord] { moments.sorted { $0.index < $1.index } }
    }

    /// One Moment of a session's transcript (D-019), with the user's review decision (spec 010).
    @Model
    public final class MomentRecord {
        public var session: CaptureSession?
        public var index: Int
        public var startSec: Double
        public var endSec: Double
        public var text: String
        /// D-024 layout: one line per transcriber result, blank line at a stanza gap.
        public var poemText: String
        public var meanConfidence: Double?
        /// `HallucinationFlag` raw values over the Moment's segments.
        public var flagsRaw: [String]
        /// `[TranscriptSegment]` as JSON: word timings and confidences for highlighting and the editor.
        public var segmentsData: Data
        /// `MomentReview` raw value.
        public var reviewRaw: String
        @Relationship(deleteRule: .nullify, inverse: \Poem.moment)
        public var poem: Poem?

        public init(_ draft: MomentDraft) {
            index = draft.index
            startSec = draft.startSec
            endSec = draft.endSec
            text = draft.text
            poemText = draft.poemText
            meanConfidence = draft.meanConfidence
            flagsRaw = draft.flags.map(\.rawValue)
            segmentsData = draft.segmentsData
            reviewRaw = MomentReview.new.rawValue
        }

        public var review: MomentReview {
            get { MomentReview(rawValue: reviewRaw) ?? .new }
            set { reviewRaw = newValue.rawValue }
        }

        public var flags: [HallucinationFlag] { flagsRaw.compactMap(HallucinationFlag.init(rawValue:)) }

        public var segments: [TranscriptSegment] {
            (try? SessionFileCodec.decoder.decode([TranscriptSegment].self, from: segmentsData)) ?? []
        }
    }

    /// A poem the user kept. Outlives its Moment and session (spec 009 R4); created from spec 010 on.
    @Model
    public final class Poem {
        #Unique<Poem>([\.id])

        public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var title: String?
        public var poet: String?
        /// `\n` line breaks, blank line between stanzas.
        public var body: String
        public var tags: [String]
        public var sourceNote: String?
        public var userEdited: Bool
        /// Provenance that survives the Moment's deletion.
        public var sourceSessionID: String?
        public var moment: MomentRecord?

        public init(body: String, createdAt: Date = Date(), sourceSessionID: String? = nil) {
            id = UUID()
            self.createdAt = createdAt
            updatedAt = createdAt
            self.body = body
            tags = []
            userEdited = false
            self.sourceSessionID = sourceSessionID
        }
    }
}

public typealias CaptureSession = LibrarySchemaV1.CaptureSession
public typealias MomentRecord = LibrarySchemaV1.MomentRecord
public typealias Poem = LibrarySchemaV1.Poem

/// Lightweight steps are added here as later schemas appear; v1 has none.
public enum LibraryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// What the store remembers about a session; live states come from the capture controller and the queue.
public enum StoredSessionState: String, Sendable, Codable, CaseIterable {
    case saved, transcribed, failed
}

public enum MomentReview: String, Sendable, Codable, CaseIterable {
    case new, saved, dismissed
}

extension ModelContainer {
    /// The library container. CloudKit is always off: `ModelConfiguration` defaults to `.automatic`, and the app
    /// makes no network use (CLAUDE.md invariant 1). `url` nil = in memory (tests, previews).
    public static func library(at url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = if let url {
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                  configurations: [configuration])
    }
}
