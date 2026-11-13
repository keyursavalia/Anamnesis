import Foundation

/// The G5 timings of one session (spec 008 R8, AC2/AC3).
public struct SessionMetrics: Sendable, Equatable, Codable {
    /// `capture.json` as it was when the job finished; nil for a session captured before spec 008.
    public var capture: CaptureRecord?
    public var transcriptionStartedAt: Date
    public var readyAt: Date
    public var audioSec: Double

    public init(capture: CaptureRecord?, transcriptionStartedAt: Date, readyAt: Date, audioSec: Double) {
        self.capture = capture
        self.transcriptionStartedAt = transcriptionStartedAt
        self.readyAt = readyAt
        self.audioSec = audioSec
    }

    /// From the moment the user could expect a transcript (the stop, or the first foreground after a background
    /// stop) to the transcript being ready.
    public var latencySec: Double? {
        guard let stoppedAt = capture?.stoppedAt else { return nil }
        let expectedFrom = max(stoppedAt, capture?.foregroundedAt ?? stoppedAt)
        return readyAt.timeIntervalSince(expectedFrom)
    }

    /// AC2: latency per second of audio; must be ≤ 1.
    public var latencyRatio: Double? {
        guard let latencySec, audioSec > 0 else { return nil }
        return latencySec / audioSec
    }

    /// Wall time of the job itself (model checks included).
    public var jobSec: Double { readyAt.timeIntervalSince(transcriptionStartedAt) }
}

/// `transcript.json` of one spool session (spec 008 R6): what the Captures screen shows. Spec 006 migrates it
/// into the library.
public struct SessionTranscript: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public var version = SessionTranscript.currentVersion
    public var sessionID: String
    public var transcript: Transcript
    public var moments: [Moment]
    public var metrics: SessionMetrics

    public init(sessionID: String, transcript: Transcript, metrics: SessionMetrics,
                momentConfig: MomentConfig = MomentConfig()) {
        self.sessionID = sessionID
        self.transcript = transcript
        moments = transcript.moments(config: momentConfig)
        self.metrics = metrics
    }

    /// Row preview: the first result's text.
    public var firstLine: String? { moments.first?.segments.first?.text }

    public static func read(from url: URL) throws -> SessionTranscript {
        try decode(from: Data(contentsOf: url))
    }

    public static func decode(from data: Data) throws -> SessionTranscript {
        try SessionFileCodec.decode(SessionTranscript.self, from: data, currentVersion: currentVersion)
    }

    public func jsonData() throws -> Data {
        try SessionFileCodec.encode(self)
    }

    /// Temp file + rename: a job killed mid-write leaves no transcript, so it reruns (R4).
    public func write(to url: URL) throws {
        try jsonData().write(to: url, options: .atomic)
    }
}
