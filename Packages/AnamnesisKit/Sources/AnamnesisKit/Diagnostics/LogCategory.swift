import os

/// Log categories shared by `os.Logger` and `FileLog` (CONVENTIONS §6).
public enum LogCategory: String, Sendable, CaseIterable {
    case capture
    case spool
    case transcribe
    case ui // swiftlint:disable:this identifier_name
    case lab
}

extension Logger {
    /// A logger under the app's subsystem for one component category.
    public init(category: LogCategory) {
        self.init(subsystem: AppIdentifiers.logSubsystem, category: category.rawValue)
    }
}
