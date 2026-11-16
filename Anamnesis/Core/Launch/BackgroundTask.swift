import UIKit

/// A `UIApplication` background task that ends exactly once: when the work is done, or when its time runs out.
/// A task still open at expiry gets the app killed, so the expiry ends it too (and logs it).
final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String, log: AppLog) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            log.error("\(name) background task expired before its work finished")
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
