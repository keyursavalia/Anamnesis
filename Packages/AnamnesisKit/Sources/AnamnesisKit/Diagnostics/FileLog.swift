import Foundation
import Synchronization

/// Size-bounded on-disk log so the owner can export logs from the device without Console.app.
///
/// Implemented as two rotating files (`current` + `previous`), each at most half the capacity:
/// when `current` would overflow it replaces `previous`, so the oldest half is dropped in one step
/// and total disk use never exceeds `capacityBytes`. Logs survive relaunches.
///
/// Thread-safe, but `append` does synchronous file I/O: never call it from a real-time audio
/// callback (CLAUDE.md invariant 6). One instance per directory per process — two processes
/// (app + extension) must use different directories, since rotation is not coordinated across processes.
public final class FileLog: Sendable {
    public enum Level: String, Sendable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case notice = "NOTICE"
        case error = "ERROR"
        case fault = "FAULT"
    }

    public static let defaultCapacityBytes = 256 * 1024

    public let capacityBytes: Int
    private let currentURL: URL
    private let previousURL: URL
    private let now: @Sendable () -> Date
    private let state: Mutex<State>

    private struct State {
        var handle: FileHandle
        var currentSize: Int
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public init(
        directory: URL,
        capacityBytes: Int = FileLog.defaultCapacityBytes,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        precondition(capacityBytes >= 1024, "FileLog capacity too small to hold a line")
        self.capacityBytes = capacityBytes
        self.now = now
        currentURL = directory.appending(path: "anamnesis.0.log")
        previousURL = directory.appending(path: "anamnesis.1.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let handle = try Self.openForAppending(currentURL)
        let size = try Int(handle.seekToEnd())
        state = Mutex(State(handle: handle, currentSize: size))
    }

    deinit {
        state.withLock { try? $0.handle.close() }
    }

    /// Appends `ISO8601 [LEVEL] [category] message`. I/O failures are swallowed: logging must never fail the caller.
    public func append(_ message: String, level: Level = .info, category: LogCategory) {
        let line = formatLine(message, level: level, category: category)
        state.withLock { state in
            if state.currentSize + line.count > capacityBytes / 2 {
                rotate(&state)
            }
            do {
                try state.handle.write(contentsOf: line)
                state.currentSize += line.count
            } catch {
                // Nowhere better to report a logging failure; dropping the line is the safe choice.
            }
        }
    }

    /// The retained log, oldest line first.
    public func snapshot() -> String {
        state.withLock { _ in
            let previous = (try? Data(contentsOf: previousURL)) ?? Data()
            let current = (try? Data(contentsOf: currentURL)) ?? Data()
            // Lossy on purpose: a damaged byte must not hide the rest of the log.
            // swiftlint:disable:next optional_data_string_conversion
            return String(decoding: previous + current, as: UTF8.self)
        }
    }

    /// Writes the retained log to `url` atomically (e.g. a temp file handed to `ShareLink`).
    public func export(to url: URL) throws {
        try Data(snapshot().utf8).write(to: url, options: .atomic)
    }

    // MARK: - Private

    private func formatLine(_ message: String, level: Level, category: LogCategory) -> Data {
        let prefix = "\(now().formatted(Self.timestampStyle)) [\(level.rawValue)] [\(category.rawValue)] "
        var line = Data((prefix + message).utf8)
        // A single line may not exceed one file's budget, otherwise rotation could not bound disk use.
        let maxLineBytes = capacityBytes / 2 - 1
        if line.count > maxLineBytes {
            // Back off to a scalar boundary (skip UTF-8 continuation bytes 0b10xxxxxx) so the file stays valid UTF-8.
            var end = line.startIndex + maxLineBytes - 3
            while end > line.startIndex, line[end] & 0xC0 == 0x80 { end -= 1 }
            line = line[..<end] + Data("...".utf8)
        }
        line.append(UInt8(ascii: "\n"))
        return line
    }

    private func rotate(_ state: inout State) {
        let fileManager = FileManager.default
        do {
            try state.handle.close()
            if fileManager.fileExists(atPath: previousURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: previousURL)
            }
            try fileManager.moveItem(at: currentURL, to: previousURL)
            state.handle = try Self.openForAppending(currentURL)
            state.currentSize = 0
        } catch {
            // Fall back to truncating `current` so the size bound still holds.
            if let handle = try? Self.openForAppending(currentURL) {
                try? handle.truncate(atOffset: 0)
                state.handle = handle
                state.currentSize = 0
            }
        }
    }

    private static func openForAppending(_ url: URL) throws -> FileHandle {
        let path = url.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: path) {
            guard FileManager.default.createFile(atPath: path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }
}
