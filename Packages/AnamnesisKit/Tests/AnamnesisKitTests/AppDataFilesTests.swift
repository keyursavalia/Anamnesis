import Foundation
import Testing
@testable import AnamnesisKit

@Suite("App data files")
struct AppDataFilesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "AppDataFilesTests-\(UUID().uuidString)")

    /// Spool/s1/{audio 100 B, transcript 20 B}, Spool/.hidden 5 B, Probes/r.json 7 B, Library.store 50 B.
    func seed() throws {
        let files: [(String, Int)] = [("Spool/s1/seg-0000.caf", 100), ("Spool/s1/transcript.json", 20),
                                      ("Spool/.hidden", 5), ("Probes/r.json", 7), ("Library.store", 50)]
        for (path, bytes) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: url)
        }
    }

    @Test("sizes and listings include nested and hidden files")
    func listing() throws {
        try seed()
        #expect(AppDataFiles.size(of: root.appending(path: "Spool")) == 125)
        #expect(AppDataFiles.size(of: root.appending(path: "Library.store")) == 50)
        #expect(AppDataFiles.size(of: root.appending(path: "Missing")) == 0)
        #expect(AppDataFiles.files(under: root).map(\.path)
                == ["Library.store", "Probes/r.json", "Spool/.hidden", "Spool/s1/seg-0000.caf",
                    "Spool/s1/transcript.json"])
    }

    @Test("removing contents empties the folder and keeps it; a missing folder is fine (AC1)")
    func remove() throws {
        try seed()
        try AppDataFiles.removeContents(of: root.appending(path: "Spool"))
        try AppDataFiles.removeContents(of: root.appending(path: "Probes"))
        try AppDataFiles.removeContents(of: root.appending(path: "Missing"))
        #expect(AppDataFiles.files(under: root).map(\.path) == ["Library.store"])
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Spool").path(percentEncoded: false),
                                               isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}
