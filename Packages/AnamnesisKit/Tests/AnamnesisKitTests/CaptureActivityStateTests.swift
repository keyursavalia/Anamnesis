import Foundation
import Testing
@testable import AnamnesisKit

@Suite("CaptureActivityState")
struct CaptureActivityStateTests {
    @Test("round-trips through JSON in every phase")
    func roundTrip() throws {
        let states: [CaptureActivityState] = [
            .awaitingConsent,
            .listening(since: Date(timeIntervalSince1970: 1_000), sessionID: "20261113T100000Z-abcd"),
            .stopped(sessionID: "20261113T100000Z-abcd", capturedSeconds: 134),
            .stopped(sessionID: nil, capturedSeconds: 0)
        ]
        for state in states {
            let data = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(CaptureActivityState.self, from: data) == state)
        }
    }

    @Test("stays far below the ActivityKit payload limit")
    func small() throws {
        let state = CaptureActivityState(phase: .listening, startedAt: Date(), capturedSeconds: 3_600,
                                         sessionID: "20261113T100000Z-abcd")
        #expect(try JSONEncoder().encode(state).count < 512)
    }

    @Test("a stop with audio in a session is saved and links to it")
    func stoppedWithAudio() {
        let state = CaptureActivityState.stopped(sessionID: "s1", capturedSeconds: 12.5)
        #expect(state.phase == .saved)
        #expect(state.capturedSeconds == 12.5)
        #expect(state.sessionURL == SessionLink(sessionID: "s1").url)
        #expect(state.dismissalDelay == 15 * 60)
        #expect(!state.isActive)
    }

    @Test("a stop without audio or without a session failed and is dismissed at once",
          arguments: [(String?.some("s1"), 0.0), (nil, 30.0), ("s1", -1.0)])
    func stoppedWithoutAudio(sessionID: String?, seconds: Double) {
        let state = CaptureActivityState.stopped(sessionID: sessionID, capturedSeconds: seconds)
        #expect(state.phase == .failed)
        #expect(state.dismissalDelay == 0)
    }

    @Test("only awaiting consent and listening are active")
    func active() {
        #expect(CaptureActivityState.awaitingConsent.isActive)
        #expect(CaptureActivityState.listening(since: Date(), sessionID: nil).isActive)
        #expect(CaptureActivityState.awaitingConsent.sessionURL == nil)
    }

    @Test("formats durations as m:ss, and h:mm:ss from an hour",
          arguments: [(0.0, "0:00"), (9.4, "0:09"), (59.6, "1:00"), (134, "2:14"), (3_599, "59:59"),
                      (3_600, "1:00:00"), (3_725, "1:02:05"), (-5, "0:00")])
    func formats(seconds: Double, expected: String) {
        #expect(CaptureActivityState.formatDuration(seconds) == expected)
    }
}
