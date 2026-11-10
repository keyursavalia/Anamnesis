import AVFAudio
import Foundation
import Testing
@testable import AnamnesisKit

@Suite("SpoolRecovery and retention")
struct SpoolRecoveryTests {
    let root = SpoolDirectory(
        root: FileManager.default.temporaryDirectory.appending(path: "SpoolRecoveryTests-\(UUID().uuidString)"))

    /// A finished 1.5-s session in 1-s segments (16 000 + 8 000 frames), then made "unfinished" by removing DONE.
    func makeInterruptedSession(id: String = UUID().uuidString) throws -> SpoolSession {
        var configuration = SegmentedSpoolWriter.Configuration()
        configuration.format = SpoolFormat(sampleRate: 16_000, channels: 1, segmentSeconds: 1)
        let writer = try SegmentedSpoolWriter(session: root.makeSession(id: id), configuration: configuration)
        let source = SyntheticPCM.pattern(count: 24_000)
        for start in stride(from: 0, to: source.count, by: 320) {
            writer.enqueue(int16: Array(source[start..<start + 320]))
        }
        writer.finish()
        try FileManager.default.removeItem(at: writer.session.doneURL)
        return writer.session
    }

    func truncate(_ url: URL, to length: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(length))
        try handle.close()
    }

    @Test("a session with intact segments is recovered with the same frames, once")
    func intact() throws {
        let session = try makeInterruptedSession()
        let result = try #require(SpoolRecovery.recover(session))
        #expect(result.state == .recovered)
        #expect(result.frames == 24_000)
        #expect(result.discardedFiles.isEmpty)
        #expect(session.isDone)
        let manifest = try SpoolManifest.read(from: session.manifestURL)
        #expect(manifest.state == .recovered)
        #expect(manifest.segments.map(\.startOffsetSec) == [0, 1])
        // Idempotent: a recovered session is final.
        #expect(SpoolRecovery.recover(session) == nil)
    }

    @Test("truncating the last segment at any byte never crashes and keeps the manifest consistent")
    func truncationProperty() throws {
        let template = try makeInterruptedSession(id: "template")
        let lastURL = template.segmentURL(2)
        let size = try #require(try lastURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        var generator = SeededGenerator(seed: 0x5EED)
        // 0 bytes, header-only sizes, the exact size, and 50 random offsets.
        let offsets = [0, 4, 8, 64, 4_096, size] + (0..<50).map { _ in Int.random(in: 0...size, using: &generator) }

        for (trial, offset) in offsets.enumerated() {
            let session = SpoolSession(directory: root.root.appending(path: "trial-\(trial)"))
            try FileManager.default.copyItem(at: template.directory, to: session.directory)
            try truncate(session.segmentURL(2), to: offset)

            let result = try #require(SpoolRecovery.recover(session))
            let manifest = try SpoolManifest.read(from: session.manifestURL)
            #expect(result.state == .recovered)
            #expect(manifest.segments.first?.frames == 16_000, "trial \(trial) offset \(offset)")
            #expect(manifest.totalFrames <= 24_000)
            if let last = manifest.segments.last, manifest.segments.count == 2 {
                #expect(last.frames > 0 && last.frames <= 8_000)
                #expect(SpoolRecovery.validate(session.segmentURL(2))?.frames == last.frames)
            } else {
                #expect(result.discardedFiles == [SpoolSession.segmentFileName(2)])
                #expect(session.segmentFiles().count == 1)
            }
        }
    }

    @Test("a missing manifest is rebuilt from the files")
    func missingManifest() throws {
        let session = try makeInterruptedSession()
        try FileManager.default.removeItem(at: session.manifestURL)
        let result = try #require(SpoolRecovery.recover(session))
        #expect(result.manifestWasMissing)
        #expect(result.frames == 24_000)
        let manifest = try SpoolManifest.read(from: session.manifestURL)
        #expect(manifest.format.sampleRate == 16_000)
        #expect(manifest.sessionID == session.id)
    }

    @Test("segments listed in the manifest but missing on disk are dropped")
    func manifestAheadOfFiles() throws {
        let session = try makeInterruptedSession()
        var manifest = try SpoolManifest.read(from: session.manifestURL)
        manifest.segments.append(SpoolSegmentInfo(
            index: 3, fileName: SpoolSession.segmentFileName(3), startOffsetSec: 1.5, frames: 16_000,
            wallStart: Date(), closedCleanly: true))
        try manifest.write(to: session.manifestURL)

        let result = try #require(SpoolRecovery.recover(session))
        #expect(result.frames == 24_000)
        #expect(try SpoolManifest.read(from: session.manifestURL).segments.map(\.index) == [1, 2])
    }

    @Test("a session without readable audio is marked interrupted")
    func nothingReadable() throws {
        let session = try root.makeSession(id: "empty")
        try Data("not audio".utf8).write(to: session.segmentURL(1))
        let result = try #require(SpoolRecovery.recover(session))
        #expect(result.state == .interrupted)
        #expect(result.discardedFiles == ["seg-000001.caf"])
        #expect(session.isDone)
    }

    @Test("recoverAll skips active and finished sessions")
    func recoverAll() throws {
        let active = try makeInterruptedSession(id: "a-active")
        let stale = try makeInterruptedSession(id: "b-stale")
        let done = try makeInterruptedSession(id: "c-done")
        try Data().write(to: done.doneURL)

        let results = SpoolRecovery.recoverAll(in: root, excluding: [active.id])
        #expect(results.map(\.sessionID) == [stale.id])
        #expect(!active.isDone)
    }

    @Test("retention defaults to deleting after transcription; delete removes the folder")
    func retention() throws {
        #expect(SpoolRetentionPolicy.default.deletesAfterTranscription)
        #expect(!SpoolRetentionPolicy.keepForDebug.deletesAfterTranscription)
        let session = try makeInterruptedSession()
        try root.delete(session)
        #expect(root.sessions().isEmpty)
    }

    @Test("delete refuses folders outside the spool root")
    func deleteOutsideRoot() throws {
        let outside = SpoolSession(directory: FileManager.default.temporaryDirectory.appending(path: "elsewhere"))
        #expect(throws: SpoolError.self) { try root.delete(outside) }
    }
}

/// SplitMix64: reproducible "random" offsets so a failing trial can be replayed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
