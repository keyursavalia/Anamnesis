import AnamnesisKit
import os

/// Writes to `os.Logger` and mirrors to `FileLog` so the owner can export logs without Console.app (CONVENTIONS §6).
/// Messages are our own state descriptions (never transcript text), so they are logged as public.
nonisolated struct AppLog: Sendable {
    let category: LogCategory
    let fileLog: FileLog?
    private let logger: Logger

    init(category: LogCategory, fileLog: FileLog?) {
        self.category = category
        self.fileLog = fileLog
        logger = Logger(category: category)
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        fileLog?.append(message, level: .notice, category: category)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        fileLog?.append(message, level: .error, category: category)
    }
}
