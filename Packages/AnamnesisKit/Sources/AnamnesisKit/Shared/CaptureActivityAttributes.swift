import Foundation
#if os(iOS)
import ActivityKit
#endif

/// The capture Live Activity (spec 007), shared by the app, which starts and updates it, and the controls
/// extension, which draws it. Nothing static: everything the UI shows changes during a capture.
public struct CaptureActivityAttributes: Codable, Hashable, Sendable {
    public typealias ContentState = CaptureActivityState

    public init() {}
}

// `ActivityAttributes` is unavailable on macOS, where the package's tests also run.
#if os(iOS)
extension CaptureActivityAttributes: ActivityAttributes {}
#endif

/// What the activity shows (R1). JSON-encoded by ActivityKit: no transcript text, no audio, and small.
public struct CaptureActivityState: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Sendable {
        /// The control was switched on; the screen-sharing picker is up.
        case awaitingConsent
        case listening
        /// Stopped with audio in the spool; the app transcribes it on the next foreground (D-020).
        case saved
        /// Stopped without audio.
        case failed
    }

    public var phase: Phase
    public var startedAt: Date?
    public var capturedSeconds: Double?
    /// The spool session the capture writes, for `SessionLink`.
    public var sessionID: String?

    public init(phase: Phase, startedAt: Date? = nil, capturedSeconds: Double? = nil, sessionID: String? = nil) {
        self.phase = phase
        self.startedAt = startedAt
        self.capturedSeconds = capturedSeconds
        self.sessionID = sessionID
    }

    public static let awaitingConsent = CaptureActivityState(phase: .awaitingConsent)

    public static func listening(since startedAt: Date, sessionID: String?) -> CaptureActivityState {
        CaptureActivityState(phase: .listening, startedAt: startedAt, sessionID: sessionID)
    }

    /// After any stop (R3): `saved` when the run left audio in a session, `failed` otherwise.
    public static func stopped(sessionID: String?, capturedSeconds: Double) -> CaptureActivityState {
        guard let sessionID, capturedSeconds > 0 else {
            return CaptureActivityState(phase: .failed, capturedSeconds: max(capturedSeconds, 0), sessionID: sessionID)
        }
        return CaptureActivityState(phase: .saved, capturedSeconds: capturedSeconds, sessionID: sessionID)
    }

    /// A capture is under way, or about to be (picker up).
    public var isActive: Bool { phase == .awaitingConsent || phase == .listening }

    /// When the activity should stop claiming to be current (spec 017 R2), so a process that died mid-capture, or a
    /// picker nobody answered, does not leave "Ready" or "Listening" up for hours. Ended phases never go stale.
    /// Travels with the content the app already sends: no extra ActivityKit call (spec 007 R8).
    public func staleDate(from now: Date) -> Date? {
        switch phase {
        case .awaitingConsent: now.addingTimeInterval(Self.consentStaleAfter)
        case .listening: (startedAt ?? now).addingTimeInterval(Self.listeningStaleAfter)
        case .saved, .failed: nil
        }
    }

    /// The picker is answered in seconds; three minutes means it was abandoned or the app went away.
    public static let consentStaleAfter: TimeInterval = 3 * 60
    /// Far past a normal scrolling session (soak runs were 30 min, F-041); the view then asks to check, it keeps the
    /// timer.
    public static let listeningStaleAfter: TimeInterval = 2 * 60 * 60

    /// How long the ended activity stays on the Lock Screen (R6): 15 min once saved, otherwise gone at once.
    public var dismissalDelay: TimeInterval { phase == .saved ? 15 * 60 : 0 }

    /// Opens the app on the captured session (R5); nil before a session exists.
    public var sessionURL: URL? { sessionID.map { SessionLink(sessionID: $0).url } }

    /// `capturedSeconds` as `m:ss`, or `h:mm:ss` from an hour; nil when unknown.
    public var formattedDuration: String? { capturedSeconds.map(Self.formatDuration) }

    public static func formatDuration(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded())
        let hours = total / 3600
        let minutes = total / 60 % 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
