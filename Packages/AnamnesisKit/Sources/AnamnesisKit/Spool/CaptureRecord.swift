import Foundation

/// Battery and thermal state at one instant (spec 008 R8). The app reads `UIDevice`/`ProcessInfo` and passes
/// plain values in; nothing here imports UIKit.
public struct PowerSnapshot: Sendable, Equatable, Codable {
    /// `UIDevice.BatteryState` by name.
    public enum BatteryState: String, Sendable, Codable {
        case unknown, unplugged, charging, full

        public init(from decoder: Decoder) throws {
            self = BatteryState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var takenAt: Date
    /// 0…1; nil when `UIDevice.batteryLevel` reported −1 (monitoring off, or the simulator).
    public var batteryLevel: Double?
    public var batteryState: BatteryState
    /// `ProcessInfo.ThermalState` by name, as in `DeviceSnapshot`.
    public var thermalState: String
    public var lowPowerMode: Bool

    public init(takenAt: Date, batteryLevel: Double?, batteryState: BatteryState, thermalState: String,
                lowPowerMode: Bool) {
        self.takenAt = takenAt
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
    }
}

/// `capture.json` of one spool session (spec 008 R8): when and how the capture ran. Written at start and stop;
/// `foregroundedAt` is added on the first foreground after a stop, for the G5 latency.
public struct CaptureRecord: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public var version = CaptureRecord.currentVersion
    public var sessionID: String
    public var startedAt: Date
    public var start: PowerSnapshot
    public var stoppedAt: Date?
    /// `ProbeReport.StopReason` raw value, e.g. "user" (indicator or Stop), "system", "error".
    public var stopReason: String?
    public var stop: PowerSnapshot?
    public var foregroundedAt: Date?

    public init(sessionID: String, startedAt: Date, start: PowerSnapshot) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.start = start
    }

    public mutating func markStopped(at date: Date, reason: String, power: PowerSnapshot) {
        stoppedAt = date
        stopReason = reason
        stop = power
    }

    /// Only the first foreground after the stop counts; earlier or later calls are ignored.
    public mutating func markForegrounded(at date: Date) {
        guard let stoppedAt, foregroundedAt == nil, date >= stoppedAt else { return }
        foregroundedAt = date
    }

    public var durationSec: Double? { stoppedAt.map { $0.timeIntervalSince(startedAt) } }

    /// Fraction of a full charge used (0.04 = 4 %); nil unless both levels are known and the device ran on battery
    /// for the whole capture (a charging device says nothing about drain).
    public var batteryDrop: Double? {
        guard let stop, start.batteryState == .unplugged, stop.batteryState == .unplugged,
              let first = start.batteryLevel, let last = stop.batteryLevel else { return nil }
        return first - last
    }

    public static func read(from url: URL) throws -> CaptureRecord {
        try decode(from: Data(contentsOf: url))
    }

    public static func decode(from data: Data) throws -> CaptureRecord {
        try SessionFileCodec.decode(CaptureRecord.self, from: data, currentVersion: currentVersion)
    }

    /// Temp file + rename, so a reader never sees a half-written record.
    public func write(to url: URL) throws {
        try SessionFileCodec.encode(self).write(to: url, options: .atomic)
    }
}

public enum SessionFileError: Error, Equatable {
    /// Written by a newer build; never overwritten or guessed at.
    case unsupportedVersion(found: Int)
}

/// Shared JSON settings for the per-session files (`capture.json`, `transcript.json`).
enum SessionFileCodec {
    private struct Header: Decodable {
        var version: Int
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    /// Reads `version` first so a newer file fails with a clear error rather than a missing-key one.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, currentVersion: Int) throws -> T {
        let version = try decoder.decode(Header.self, from: data).version
        guard version <= currentVersion else { throw SessionFileError.unsupportedVersion(found: version) }
        return try decoder.decode(type, from: data)
    }
}

extension SpoolSession {
    public static let captureRecordFileName = "capture.json"
    public static let transcriptFileName = "transcript.json"

    public var captureRecordURL: URL { directory.appending(path: Self.captureRecordFileName) }
    public var transcriptURL: URL { directory.appending(path: Self.transcriptFileName) }
    public var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptURL.path(percentEncoded: false)) }
    public var hasAudio: Bool { !segmentFiles().isEmpty }
}
