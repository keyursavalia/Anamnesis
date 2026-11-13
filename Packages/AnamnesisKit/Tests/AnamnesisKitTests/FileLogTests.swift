import Foundation
import Testing
@testable import AnamnesisKit

@Suite("FileLog")
struct FileLogTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "FileLogTests-\(UUID().uuidString)")
    }

    private func lines(_ log: FileLog) -> [String] {
        log.snapshot().split(separator: "\n").map(String.init)
    }

    private func diskUsage() throws -> Int {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        return try names.reduce(0) { total, name in
            let attributes = try FileManager.default.attributesOfItem(
                atPath: directory.appending(path: name).path(percentEncoded: false))
            return total + ((attributes[.size] as? Int) ?? 0)
        }
    }

    @Test("formats lines as ISO8601 [LEVEL] [category] message")
    func lineFormat() throws {
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let log = try FileLog(directory: directory, now: { fixed })
        log.append("stream started", level: .notice, category: .capture)
        #expect(lines(log) == ["2027-01-15T08:00:00.000Z [NOTICE] [capture] stream started"])
    }

    @Test("snapshot keeps lines in append order")
    func ordering() throws {
        let log = try FileLog(directory: directory)
        for index in 0..<50 { log.append("line \(index)", category: .lab) }
        let messages = lines(log).map { $0.components(separatedBy: "] ").last ?? "" }
        #expect(messages == (0..<50).map { "line \($0)" })
    }

    @Test("appending beyond capacity drops the oldest lines and bounds disk use")
    func capacity() throws {
        let capacity = 4 * 1024
        let log = try FileLog(directory: directory, capacityBytes: capacity)
        for index in 0..<1_000 { log.append("line \(index)", category: .spool) }

        let retained = lines(log)
        #expect(log.snapshot().utf8.count <= capacity)
        #expect(try diskUsage() <= capacity)
        #expect(retained.last?.hasSuffix("line 999") == true)
        #expect(!retained.contains { $0.hasSuffix(" line 0") })
        // Rotation drops at most half the budget, so a reasonable tail survives.
        #expect(retained.count > 30)
    }

    @Test("an oversized line is truncated to fit")
    func oversizedLine() throws {
        let capacity = 2 * 1024
        let log = try FileLog(directory: directory, capacityBytes: capacity)
        log.append(String(repeating: "é", count: 5_000), category: .ui)
        let snapshot = log.snapshot()
        #expect(snapshot.utf8.count <= capacity / 2)
        #expect(snapshot.hasSuffix("...\n"))
    }

    @Test("retained log survives reopening the same directory")
    func persistence() throws {
        do {
            let log = try FileLog(directory: directory)
            log.append("before relaunch", category: .lab)
        }
        let reopened = try FileLog(directory: directory)
        reopened.append("after relaunch", category: .lab)
        let retained = lines(reopened)
        #expect(retained.count == 2)
        #expect(retained.first?.hasSuffix("before relaunch") == true)
    }

    @Test("concurrent appends neither crash nor lose or corrupt lines")
    func concurrency() async throws {
        let log = try FileLog(directory: directory, capacityBytes: 1024 * 1024)
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for index in 0..<200 { log.append("w\(worker) i\(index)", category: .capture) }
                }
            }
        }
        let retained = lines(log)
        #expect(retained.count == 1_600)
        #expect(retained.allSatisfy { $0.contains(" [INFO] [capture] w") })
    }

    @Test("concurrent appends across rotations stay within capacity")
    func concurrentRotation() async throws {
        let capacity = 8 * 1024
        let log = try FileLog(directory: directory, capacityBytes: capacity)
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for index in 0..<500 { log.append("w\(worker) i\(index)", category: .capture) }
                }
            }
        }
        #expect(try diskUsage() <= capacity)
        #expect(lines(log).allSatisfy { $0.contains(" [INFO] [capture] w") })
    }

    @Test("export writes the snapshot to the given URL")
    func export() throws {
        let log = try FileLog(directory: directory)
        log.append("exported", level: .error, category: .transcribe)
        let target = directory.appending(path: "export.txt")
        try log.export(to: target)
        #expect(try String(contentsOf: target, encoding: .utf8) == log.snapshot())
    }

    @Test("clear empties both files and the next line is the only one")
    func clear() throws {
        let log = try FileLog(directory: directory, capacityBytes: 1024)
        for index in 0..<40 { log.append("line \(index)", category: .ui) }
        log.clear()
        #expect(log.snapshot().isEmpty)
        log.append("after", category: .ui)
        #expect(lines(log).count == 1)
        #expect(lines(log).first?.hasSuffix("after") == true)
        #expect(try diskUsage() < 100)
    }
}
