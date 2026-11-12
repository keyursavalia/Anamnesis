import Foundation
import Synchronization

/// In-process hand-off from the control's intent (which the system runs inside the app, spec 005 F-028) to the UI.
/// Keeps only the latest link so a post made before the UI subscribes, e.g. during a cold launch, is not lost.
public final class CaptureLaunchMailbox: Sendable {
    public static let shared = CaptureLaunchMailbox()
    /// Posted (on the poster's thread) after every `post`; observers then call `take()`.
    public static let didPost = Notification.Name("\(AppIdentifiers.appBundleID).captureLaunch.didPost")

    private let pending = Mutex<CaptureLaunchLink?>(nil)
    private let inPlaceCheck = Mutex<(@Sendable () async -> Bool)?>(nil)

    init() {}

    public func post(_ link: CaptureLaunchLink, center: NotificationCenter = .default) {
        pending.withLock { $0 = link }
        center.post(name: Self.didPost, object: nil)
    }

    /// Registered by the app: whether the picker can be presented right now without bringing the app forward.
    /// From a cold background launch the picker is deferred until the app is next opened (F-031).
    public func setInPlaceCheck(_ check: @escaping @Sendable () async -> Bool) {
        inPlaceCheck.withLock { $0 = check }
    }

    /// Waits up to `timeout` for the app to register its check (a cold launch may still be starting), then runs it.
    /// False if none is registered in time (e.g. when called from the widget extension).
    public func canPresentInPlace(timeout: Duration = .seconds(1)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let check = inPlaceCheck.withLock({ $0 }) { return await check() }
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Returns the pending link once; nil until the next `post`.
    public func take() -> CaptureLaunchLink? {
        pending.withLock { pending in
            defer { pending = nil }
            return pending
        }
    }
}
