import AnamnesisKit
import Foundation

/// A capture deep link as the app received it (spec 005). Lives in `AppEnvironment` so its one-shot flags
/// survive the capture screen being rebuilt.
struct LaunchRequest: Identifiable {
    let id = UUID()
    let link: CaptureLaunchLink
    let receivedAt: Date
    /// Cleared once the picker has been presented for this request, so re-entering the screen does not loop (rung 2).
    var autoPresentPending: Bool
    /// Cleared once the tap → first-buffer timing has been written into the run's report.
    var timingPending = true
    /// When the picker was requested for this launch (operator tap in rung 1, on arrival in 2, from the intent in 3).
    var startRequestedAt: Date?

    init(link: CaptureLaunchLink, receivedAt: Date = Date()) {
        self.link = link
        self.receivedAt = receivedAt
        autoPresentPending = link.rung == .onArrival
    }

    var rung: Int { link.rung.rawValue }
}
