import Foundation
import Synchronization

/// In-process hand-off from the control's intent (which the system runs inside the app, spec 005 F-028) to the UI.
/// Keeps only the latest command so a post made before the app subscribes, e.g. during a cold launch, is not lost.
public final class CaptureLaunchMailbox: Sendable {
    public enum Command: Sendable, Equatable {
        case start(CaptureLaunchLink)
        /// The control was switched off.
        case stop
    }

    public static let shared = CaptureLaunchMailbox()
    /// Posted (on the poster's thread) after every `post`; observers then call `take()`.
    public static let didPost = Notification.Name("\(AppIdentifiers.appBundleID).captureLaunch.didPost")

    private let pending = Mutex<Command?>(nil)

    init() {}

    public func post(_ command: Command, center: NotificationCenter = .default) {
        pending.withLock { $0 = command }
        center.post(name: Self.didPost, object: nil)
    }

    /// Returns the pending command once; nil until the next `post`.
    public func take() -> Command? {
        pending.withLock { pending in
            defer { pending = nil }
            return pending
        }
    }
}
