import Foundation
import Testing
@testable import AnamnesisKit

@Suite("CaptureControlState")
struct CaptureControlStateTests {
    private func withFileURL(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CaptureControlStateTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appending(path: "control-state.json"))
    }

    @Test("reads idle when nothing was written or the file is not valid")
    func missingOrCorruptIsIdle() throws {
        try withFileURL { url in
            #expect(CaptureControlState(contentsOf: url) == .idle)
            try Data("not json".utf8).write(to: url)
            #expect(CaptureControlState(contentsOf: url) == .idle)
        }
    }

    @Test("round-trips capturing, then idle")
    func roundTrip() throws {
        try withFileURL { url in
            let capturing = CaptureControlState(isCapturing: true, startedAt: Date(timeIntervalSince1970: 1_000))
            try capturing.write(to: url)
            #expect(CaptureControlState(contentsOf: url) == capturing)

            try CaptureControlState.idle.write(to: url)
            #expect(CaptureControlState(contentsOf: url) == .idle)
        }
    }

    @Test("an idle state never carries a start time")
    func idleDropsStartedAt() {
        #expect(CaptureControlState(isCapturing: false, startedAt: Date()).startedAt == nil)
    }
}
