import Foundation

/// `manifest.json` of one spool session (spec 002 R4). Replaced atomically on every rotation and at finish.
public struct SpoolManifest: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public enum State: String, Sendable, Codable {
        /// Being written (or the writer died before finishing; recovery decides).
        case active
        case finished
        /// Found without `DONE` and could not be repaired into a usable session (no readable segment).
        case interrupted
        /// Found without `DONE`; segments were validated and durations repaired from the files.
        case recovered
        /// A state written by a newer build.
        case unknown

        public init(from decoder: Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var schemaVersion = SpoolManifest.currentSchemaVersion
    public var sessionID: String
    /// Operator label of the probe run that produced it, if any.
    public var label: String?
    public var createdAt: Date
    public var finishedAt: Date?
    public var format: SpoolFormat
    public var state: State
    public var segments: [SpoolSegmentInfo]
    public var counters: SpoolCounters

    public init(
        sessionID: String, label: String? = nil, createdAt: Date, format: SpoolFormat, state: State = .active,
        segments: [SpoolSegmentInfo] = [], counters: SpoolCounters = SpoolCounters()
    ) {
        self.sessionID = sessionID
        self.label = label
        self.createdAt = createdAt
        self.format = format
        self.state = state
        self.segments = segments
        self.counters = counters
    }

    public var totalFrames: Int { segments.reduce(0) { $0 + $1.frames } }
    public var durationSec: Double { format.seconds(forFrames: totalFrames) }

    public func jsonData() throws -> Data {
        try Self.encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> SpoolManifest {
        try decoder.decode(SpoolManifest.self, from: data)
    }

    /// Temp file + rename, so a reader never sees a half-written manifest.
    public func write(to url: URL) throws {
        try jsonData().write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> SpoolManifest {
        try decode(from: Data(contentsOf: url))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct SpoolSegmentInfo: Sendable, Equatable, Codable {
    public var index: Int
    public var fileName: String
    /// Cumulative *written* seconds before this segment (gaps are not filled, spec 002 §4.2).
    public var startOffsetSec: Double
    public var frames: Int
    /// Wall-clock time the first frame was written; for reference only.
    public var wallStart: Date
    public var closedCleanly: Bool

    public init(
        index: Int, fileName: String, startOffsetSec: Double, frames: Int, wallStart: Date, closedCleanly: Bool
    ) {
        self.index = index
        self.fileName = fileName
        self.startOffsetSec = startOffsetSec
        self.frames = frames
        self.wallStart = wallStart
        self.closedCleanly = closedCleanly
    }
}

/// Writer-side counters, persisted with the manifest (CONVENTIONS §3 rule 6).
public struct SpoolCounters: Sendable, Equatable, Codable {
    /// Buffers rejected because the inbox was full (producer never waits).
    public var dropsQueueFull = 0
    public var droppedFrames = 0
    /// Buffers whose layout the inbox could not read (unsupported format or short buffer list).
    public var invalidBuffers = 0
    /// Input format changes after the first buffer; each one rebuilds the converter.
    public var formatChanges = 0
    /// Samples outside [-1, 1] that were clamped when quantizing to Int16 (F-009).
    public var clippedSamples = 0
    public var ptsGaps = ProbeReport.PTSGaps()
    /// Buffers the writer could not convert or write; the first failure's text is kept.
    public var writeErrors = 0
    public var firstError: String?

    public init() {}
}
