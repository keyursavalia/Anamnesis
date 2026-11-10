import Foundation
import Testing
@testable import AnamnesisKit

@Suite("SpoolManifest and SpoolDirectory")
struct SpoolManifestTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "SpoolManifestTests-\(UUID().uuidString)")

    static func sample() -> SpoolManifest {
        var counters = SpoolCounters()
        counters.clippedSamples = 12
        counters.ptsGaps.count = 1
        return SpoolManifest(
            sessionID: "20261109T171503Z-abcd", label: "R-020", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            format: .standard, state: .finished,
            segments: [
                SpoolSegmentInfo(index: 1, fileName: "seg-000001.caf", startOffsetSec: 0, frames: 960_000,
                                 wallStart: Date(timeIntervalSince1970: 1_800_000_000), closedCleanly: true),
                SpoolSegmentInfo(index: 2, fileName: "seg-000002.caf", startOffsetSec: 60, frames: 16_000,
                                 wallStart: Date(timeIntervalSince1970: 1_800_000_060), closedCleanly: true)
            ],
            counters: counters)
    }

    @Test("standard format is 16 kHz mono with 60-s segments")
    func standardFormat() {
        #expect(SpoolFormat.standard.segmentFrames == 960_000)
        #expect(SpoolFormat.standard.bytesPerFrame == 2)
        #expect(SpoolFormat.standard.pcmFormat?.commonFormat == .pcmFormatInt16)
    }

    @Test("round-trips through JSON")
    func roundTrip() throws {
        let manifest = Self.sample()
        let decoded = try SpoolManifest.decode(from: manifest.jsonData())
        #expect(decoded == manifest)
        #expect(decoded.totalFrames == 976_000)
        #expect(decoded.durationSec == 61)
    }

    @Test("ignores unknown fields and maps unknown states (forward compatibility)")
    func forwardCompatible() throws {
        var object = try #require(
            try JSONSerialization.jsonObject(with: Self.sample().jsonData()) as? [String: Any])
        object["futureField"] = ["nested": true]
        object["state"] = "archived"
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try SpoolManifest.decode(from: data)
        #expect(decoded.state == .unknown)
        #expect(decoded.segments.count == 2)
    }

    @Test("write replaces the manifest atomically")
    func atomicWrite() throws {
        let session = try SpoolDirectory(root: root).makeSession(id: "s1")
        var manifest = Self.sample()
        try manifest.write(to: session.manifestURL)
        manifest.state = .recovered
        try manifest.write(to: session.manifestURL)
        #expect(try SpoolManifest.read(from: session.manifestURL).state == .recovered)
        // No temp files left beside it.
        let names = try FileManager.default.contentsOfDirectory(atPath: session.directory.path(percentEncoded: false))
        #expect(names == [SpoolSession.manifestFileName])
    }

    @Test("segment file names are zero-padded and parse back", arguments: [1, 42, 999_999, 1_234_567])
    func segmentNames(index: Int) {
        let name = SpoolSession.segmentFileName(index)
        #expect(name.hasPrefix("seg-") && name.hasSuffix(".caf"))
        #expect(SpoolSession.segmentIndex(fileName: name) == index)
    }

    @Test("rejects files that are not segments", arguments: ["seg-.caf", "seg-12a.caf", "raw.caf", "seg-000001.wav",
                                                             "manifest.json", "seg-٣.caf"])
    func notSegments(name: String) {
        #expect(SpoolSession.segmentIndex(fileName: name) == nil)
    }

    @Test("session ids sort by creation time")
    func sessionIDs() {
        let early = SpoolDirectory.makeSessionID(createdAt: Date(timeIntervalSince1970: 1_800_000_000), suffix: "ZZZZ")
        let late = SpoolDirectory.makeSessionID(createdAt: Date(timeIntervalSince1970: 1_800_000_001), suffix: "aaaa")
        #expect(early == "20270115T080000Z-zzzz")
        #expect(early < late)
    }

    @Test("sessions are excluded from backup and listed in order")
    func sessionFolders() throws {
        let directory = SpoolDirectory(root: root)
        let second = try directory.makeSession(id: "20261109T000002Z-b")
        let first = try directory.makeSession(id: "20261109T000001Z-a")
        let values = try first.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(directory.sessions().map(\.id) == [first.id, second.id])
        #expect(!first.isDone)
    }

    @Test("lists segment files by index, ignoring other files")
    func segmentFiles() throws {
        let session = try SpoolDirectory(root: root).makeSession(id: "s2")
        for name in ["seg-000010.caf", "seg-000002.caf", "raw.caf", "manifest.json"] {
            try Data().write(to: session.directory.appending(path: name))
        }
        #expect(session.segmentFiles().map(\.index) == [2, 10])
    }
}
