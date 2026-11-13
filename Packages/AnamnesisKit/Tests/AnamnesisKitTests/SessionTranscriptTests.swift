import Foundation
import Testing
@testable import AnamnesisKit

@Suite("SessionTranscript and CaptureRecord")
struct SessionTranscriptTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "SessionTranscriptTests-\(UUID().uuidString)")
    /// Whole seconds: the files store ISO 8601 dates without fractions.
    let start = Date(timeIntervalSince1970: 1_794_000_000)

    func power(_ level: Double?, _ state: PowerSnapshot.BatteryState = .unplugged, at offset: Double = 0)
        -> PowerSnapshot {
        PowerSnapshot(takenAt: start.addingTimeInterval(offset), batteryLevel: level, batteryState: state,
                      thermalState: "nominal", lowPowerMode: false)
    }

    func record(stoppedAfter: Double? = 600, foregroundedAfter: Double? = nil,
                startLevel: Double? = 0.80, stopLevel: Double? = 0.76,
                stopState: PowerSnapshot.BatteryState = .unplugged) -> CaptureRecord {
        var record = CaptureRecord(sessionID: "s1", startedAt: start, start: power(startLevel))
        if let stoppedAfter {
            record.markStopped(at: start.addingTimeInterval(stoppedAfter), reason: "user",
                               power: power(stopLevel, stopState, at: stoppedAfter))
        }
        if let foregroundedAfter { record.markForegrounded(at: start.addingTimeInterval(foregroundedAfter)) }
        return record
    }

    func metrics(_ record: CaptureRecord?, readyAfter: Double, audioSec: Double = 600) -> SessionMetrics {
        SessionMetrics(capture: record, transcriptionStartedAt: start.addingTimeInterval(readyAfter - 10),
                       readyAt: start.addingTimeInterval(readyAfter), audioSec: audioSec)
    }

    // MARK: - CaptureRecord

    @Test("capture record round-trips through its file")
    func recordRoundTrip() throws {
        let url = root.appending(path: "capture.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = record(foregroundedAfter: 700)
        try original.write(to: url)
        #expect(try CaptureRecord.read(from: url) == original)
    }

    @Test("foregroundedAt is set once, only after the stop")
    func foregroundedOnce() {
        var running = record(stoppedAfter: nil)
        running.markForegrounded(at: start.addingTimeInterval(5))
        #expect(running.foregroundedAt == nil)

        var stopped = record()
        stopped.markForegrounded(at: start.addingTimeInterval(700))
        stopped.markForegrounded(at: start.addingTimeInterval(900))
        #expect(stopped.foregroundedAt == start.addingTimeInterval(700))
    }

    @Test("a record from a newer build is rejected")
    func recordNewerVersion() throws {
        var newer = record()
        newer.version = CaptureRecord.currentVersion + 1
        let data = try SessionFileCodec.encode(newer)
        #expect(throws: SessionFileError.unsupportedVersion(found: newer.version)) {
            try CaptureRecord.decode(from: data)
        }
    }

    @Test("an unknown battery state decodes as unknown")
    func unknownBatteryState() throws {
        let json = #"{"takenAt":"2026-11-12T00:00:00Z","batteryState":"wireless","#
            + #""thermalState":"fair","lowPowerMode":true}"#
        let snapshot = try SessionFileCodec.decoder.decode(PowerSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.batteryState == .unknown)
        #expect(snapshot.batteryLevel == nil)
    }

    // MARK: - Metrics

    @Test("latency counts from the stop when the app was in front")
    func latencyFromStop() throws {
        let metrics = metrics(record(), readyAfter: 612)
        #expect(try #require(metrics.latencySec) == 12)
        #expect(try #require(metrics.latencyRatio) == 0.02)
        #expect(metrics.jobSec == 10)
    }

    @Test("latency counts from the first foreground after a background stop")
    func latencyFromForeground() throws {
        let metrics = metrics(record(foregroundedAfter: 900), readyAfter: 915)
        #expect(try #require(metrics.latencySec) == 15)
    }

    @Test("latency is nil without a stop time or audio")
    func latencyUnknown() {
        #expect(metrics(nil, readyAfter: 10).latencySec == nil)
        #expect(metrics(record(stoppedAfter: nil), readyAfter: 10).latencySec == nil)
        #expect(metrics(record(), readyAfter: 612, audioSec: 0).latencyRatio == nil)
    }

    struct DropCase: Sendable {
        let stopLevel: Double?
        let stopState: PowerSnapshot.BatteryState
        let expected: Double?
    }

    @Test("battery drop is start minus stop, only when unplugged throughout and both levels are known",
          arguments: [
            DropCase(stopLevel: 0.76, stopState: .unplugged, expected: 0.04),
            DropCase(stopLevel: nil, stopState: .unplugged, expected: nil),
            DropCase(stopLevel: 0.90, stopState: .charging, expected: nil),
            DropCase(stopLevel: 1.0, stopState: .full, expected: nil)
          ])
    func batteryDrop(_ testCase: DropCase) {
        let drop = record(startLevel: 0.80, stopLevel: testCase.stopLevel, stopState: testCase.stopState).batteryDrop
        if let expected = testCase.expected {
            #expect(abs((drop ?? -1) - expected) < 1e-9)
        } else {
            #expect(drop == nil)
        }
    }

    @Test("capture duration is stop minus start")
    func captureDuration() {
        #expect(record().durationSec == 600)
        #expect(record(stoppedAfter: nil).durationSec == nil)
    }

    // MARK: - SessionTranscript

    func transcript() -> SessionTranscript {
        let segments = [TranscriptSegment(text: "Do not go gentle", startSec: 1, endSec: 3, confidence: 0.9),
                        TranscriptSegment(text: "into that good night", startSec: 3.2, endSec: 5, confidence: 0.4),
                        TranscriptSegment(text: "Rage, rage", startSec: 20, endSec: 22)]
        let inner = Transcript(source: "session s1", locale: "en_US", config: TranscriptionConfig(),
                               createdAt: start, segments: segments, speechRegions: nil,
                               metrics: TranscriptionMetrics(audioSec: 600, wallSec: 8, assetStatus: "installed"))
        return SessionTranscript(sessionID: "s1", transcript: inner, metrics: metrics(record(), readyAfter: 612))
    }

    @Test("builds Moments from the transcript's segments (D-019)")
    func moments() {
        let value = transcript()
        #expect(value.moments.count == 2)
        #expect(value.moments.first?.text == "Do not go gentle into that good night")
        #expect(value.firstLine == "Do not go gentle")
    }

    @Test("round-trips through its file atomically")
    func transcriptRoundTrip() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "transcript.json")
        let original = transcript()
        try original.write(to: url)
        #expect(try SessionTranscript.read(from: url) == original)
    }

    @Test("a transcript from a newer build is rejected")
    func transcriptNewerVersion() throws {
        var newer = transcript()
        newer.version = SessionTranscript.currentVersion + 1
        let data = try SessionFileCodec.encode(newer)
        #expect(throws: SessionFileError.unsupportedVersion(found: newer.version)) {
            try SessionTranscript.decode(from: data)
        }
    }

    @Test("session files live in the spool session folder")
    func paths() {
        let session = SpoolSession(directory: root.appending(path: "20261112T100000Z-abcd"))
        #expect(session.captureRecordURL.lastPathComponent == "capture.json")
        #expect(session.transcriptURL.lastPathComponent == "transcript.json")
        #expect(session.transcriptURL.deletingLastPathComponent().pathComponents == session.directory.pathComponents)
    }
}
