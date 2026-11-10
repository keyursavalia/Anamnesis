import Foundation

/// Self-describing result of one capture-probe run (spec 001 §4.3). Exported to `TestResults/`.
public struct ProbeReport: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public enum Backend: String, Sendable, Codable {
        case screenCaptureKit
        case replayKit
    }

    /// Buffer types of both backends: SCK (`screen`/`audio`/`microphone`), ReplayKit (`video`/`audioApp`/`audioMic`).
    public enum BufferType: String, Sendable, Codable, CaseIterable {
        case screen, audio, microphone
        case video, audioApp, audioMic
    }

    /// What the operator set up; filled by the backend before the run starts.
    public struct Config: Sendable, Equatable, Codable {
        public var requestedSampleRate: Int?
        public var requestedChannels: Int?
        public var width: Int?
        public var height: Int?
        public var styleUsed: String?
        /// What the picker actually returned, e.g. "display" (entire screen) or "window" (one app).
        public var filterStyle: String?
        /// The filter's content rect in points, e.g. "0 0 1024 1366".
        public var filterContentRect: String?
        public var outputsAdded: [String]
        public var backgroundModes: [String]
        /// Spool session written alongside this run (spec 002), if spooling was on.
        public var spoolSessionID: String?

        public init(
            requestedSampleRate: Int? = nil, requestedChannels: Int? = nil, width: Int? = nil, height: Int? = nil,
            styleUsed: String? = nil, filterStyle: String? = nil, filterContentRect: String? = nil,
            outputsAdded: [String] = [], backgroundModes: [String] = [], spoolSessionID: String? = nil
        ) {
            self.requestedSampleRate = requestedSampleRate
            self.requestedChannels = requestedChannels
            self.width = width
            self.height = height
            self.styleUsed = styleUsed
            self.filterStyle = filterStyle
            self.filterContentRect = filterContentRect
            self.outputsAdded = outputsAdded
            self.backgroundModes = backgroundModes
            self.spoolSessionID = spoolSessionID
        }
    }

    public struct FirstBuffer: Sendable, Equatable, Codable {
        public var type: BufferType
        public var format: AudioFormatInfo
        public var framesPerBuffer: Int
        public var timeToFirstBufferSec: Double
    }

    public struct PTSGaps: Sendable, Equatable, Codable {
        public static let maxEvents = 32

        public var count = 0
        public var maxMs = 0.0
        public var totalMs = 0.0
        /// The first `maxEvents` gaps with when they happened; optional so older reports still decode.
        public var events: [GapEvent]?
    }

    public struct GapEvent: Sendable, Equatable, Codable {
        /// Seconds since the run started (wall clock), comparable with `timeline` and `markers`.
        public var tSec: Double
        public var durationMs: Double
    }

    public struct ErrorRecord: Sendable, Equatable, Codable {
        public var tSec: Double
        public var domain: String
        public var code: Int
        public var description: String
    }

    public struct Counters: Sendable, Equatable, Codable {
        /// Keyed by `BufferType.rawValue`.
        public var byType: [String: Int] = [:]
        public var audioBuffers = 0
        public var audioFramesTotal = 0
        public var audioSecondsTotal = 0.0
        public var silentBuffers = 0
        public var silentRatio = 0.0
        /// `LevelMath.histogramBinCount` bins of per-buffer RMS dBFS.
        public var rmsHistogram = [Int](repeating: 0, count: LevelMath.histogramBinCount)
        public var ptsGaps = PTSGaps()
        public var formatChanges = 0
        public var dropsQueueFull = 0
        public var errors: [ErrorRecord] = []
    }

    public enum MarkerKind: String, Sendable, Codable {
        case audibleStart, audibleEnd, note
    }

    public struct Marker: Sendable, Equatable, Codable {
        public var tSec: Double
        public var kind: MarkerKind
        public var text: String?
    }

    public struct MemorySample: Sendable, Equatable, Codable {
        public var tSec: Double
        public var physFootprintMB: Double
        public var osAvailableMB: Double?
    }

    public struct Memory: Sendable, Equatable, Codable {
        public var samples: [MemorySample] = []
        public var peakFootprintMB = 0.0
        public var minAvailableMB: Double?
    }

    /// One entry per wall-clock second that delivered audio; missing seconds mean nothing arrived.
    public struct TimelineSecond: Sendable, Equatable, Codable {
        public var sec: Int
        public var rmsDb: Float
        public var silent: Bool
    }

    public enum StopReason: String, Sendable, Codable {
        case user, system, interruption, error, unknown
    }

    public struct Stop: Sendable, Equatable, Codable {
        public var reason: StopReason
        public var errorDomain: String?
        public var errorCode: Int?
        public var errorDescription: String?

        public init(
            reason: StopReason, errorDomain: String? = nil, errorCode: Int? = nil, errorDescription: String? = nil
        ) {
            self.reason = reason
            self.errorDomain = errorDomain
            self.errorCode = errorCode
            self.errorDescription = errorDescription
        }
    }

    public var schemaVersion = ProbeReport.currentSchemaVersion
    /// Operator-entered, e.g. "R-002 S1 C1 T2".
    public var runLabel: String
    public var backend: Backend
    public var startedAt: Date
    public var endedAt: Date?
    public var durationSec: Double
    public var device: DeviceSnapshot
    public var thermalStateAtEnd: String?
    public var app: BundleSnapshot
    public var config: Config
    public var firstBuffer: FirstBuffer?
    public var counters = Counters()
    public var markers: [Marker] = []
    public var memory = Memory()
    public var timeline: [TimelineSecond] = []
    public var stop: Stop?
    public var notes: String

    public func jsonData() throws -> Data {
        try Self.encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> ProbeReport {
        try decoder.decode(ProbeReport.self, from: data)
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
