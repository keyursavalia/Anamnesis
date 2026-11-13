import Foundation
import Testing
@testable import AnamnesisKit

@Suite("CaptureSessionState and audio retention")
struct CaptureSessionStateTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        var isActive = false
        var manifestState: SpoolManifest.State? = .finished
        var stored: StoredSessionState? = .saved
        var job: CaptureSessionState.Job?
        let expected: CaptureSessionState
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "being written", isActive: true, manifestState: .active, expected: .capturing),
        Case(name: "active wins over a stored transcript", isActive: true, stored: .transcribed, expected: .capturing),
        Case(name: "finished, waiting", expected: .saved),
        Case(name: "recovered, waiting", manifestState: .recovered, expected: .saved),
        Case(name: "manifest not yet rebuilt", manifestState: nil, expected: .saved),
        Case(name: "not in the store yet", stored: nil, expected: .saved),
        Case(name: "stored failure", stored: .failed, expected: .failed),
        Case(name: "job running", job: .running, expected: .transcribing),
        Case(name: "job failed", job: .failed, expected: .failed),
        Case(name: "nothing recoverable", manifestState: .interrupted, expected: .failed),
        Case(name: "transcript in the store", stored: .transcribed, expected: .transcribed),
        Case(name: "transcript wins over a failed rerun", stored: .transcribed, job: .failed, expected: .transcribed)
    ]

    @Test("derives the row state", arguments: cases)
    func derive(_ testCase: Case) {
        let state = CaptureSessionState(isActive: testCase.isActive, stored: testCase.stored,
                                        manifestState: testCase.manifestState, job: testCase.job)
        #expect(state == testCase.expected)
    }

    struct TranscribableCase: Sendable {
        var isDone = true
        var state = SpoolManifest.State.finished
        var hasAudio = true
        var hasTranscript = false
        let expected: Bool
    }

    @Test("only a final session with audio and no transcript is transcribable",
          arguments: [
            TranscribableCase(expected: true),
            TranscribableCase(state: .recovered, expected: true),
            TranscribableCase(isDone: false, state: .active, expected: false),
            TranscribableCase(state: .interrupted, expected: false),
            TranscribableCase(hasAudio: false, expected: false),
            TranscribableCase(hasTranscript: true, expected: false)
          ])
    func transcribable(_ testCase: TranscribableCase) {
        #expect(CaptureSessionState.isTranscribable(
            isDone: testCase.isDone, manifestState: testCase.state, hasAudio: testCase.hasAudio,
            hasTranscript: testCase.hasTranscript) == testCase.expected)
    }

    @Test("deleting audio removes the segments and keeps the session's other files")
    func deleteAudio() throws {
        let root = SpoolDirectory(root: FileManager.default.temporaryDirectory
            .appending(path: "CaptureSessionStateTests-\(UUID().uuidString)"))
        let session = try root.makeSession(id: "20261112T100000Z-abcd")
        for index in 1...3 { try Data([1, 2]).write(to: session.segmentURL(index)) }
        for url in [session.manifestURL, session.doneURL, session.captureRecordURL, session.transcriptURL] {
            try Data("{}".utf8).write(to: url)
        }
        #expect(session.hasAudio)
        #expect(try session.deleteAudio() == 3)
        #expect(!session.hasAudio)
        for url in [session.manifestURL, session.doneURL, session.captureRecordURL, session.transcriptURL] {
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
        // A DONE session without audio is never recovered again.
        #expect(SpoolRecovery.recover(session) == nil)
    }
}
