import Foundation

/// What the *Capture poem* control shows (spec 005 Step 6). The app writes it on every capture start and stop; the
/// control's value provider, which runs in the widget extension, reads it from the App Group container.
/// A file, not `UserDefaults`: a stop from the system indicator left the control on although the app had written
/// off and reloaded it (F-037); a file read has no per-process cache to go stale.
public struct CaptureControlState: Sendable, Equatable, Codable {
    public var isCapturing: Bool
    public var startedAt: Date?

    public static let idle = CaptureControlState(isCapturing: false)

    /// nil if the App Group is not in the target's entitlements.
    public static var sharedURL: URL? { groupContainer?.appending(path: "control-state.json") }

    private static var groupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupID)
    }

    public init(isCapturing: Bool, startedAt: Date? = nil) {
        self.isCapturing = isCapturing
        self.startedAt = isCapturing ? startedAt : nil
    }

    /// A missing or unreadable file reads as idle.
    public init(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(Self.self, from: data) else {
            self = .idle
            return
        }
        self = state
    }

    public func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
