import AnamnesisKit
import Observation
import WidgetKit

/// Whether the user has added the *Capture poem* control (spec 015 R9). iOS has no API to add a control for the
/// user; WidgetKit only reports which of the app's controls are placed (`ControlCenter.currentControls()`), so the
/// guide can tick itself off. What counts as "placed" (Control Center, Lock Screen, Action Button) is a device
/// finding, not a header fact.
@Observable
final class ControlCenterStatus {
    enum State: Equatable {
        /// Not asked yet; the UI shows nothing rather than a card that may vanish a moment later.
        case unknown
        case notAdded
        case added
        /// The query threw; the UI falls back to the manual guide.
        case unavailable
    }

    private(set) var state = State.unknown
    @ObservationIgnored private let log: AppLog
    @ObservationIgnored private var isRefreshing = false

    init(log: AppLog) {
        self.log = log
    }

    var isAdded: Bool { state == .added }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previous = state
        do {
            let controls = try await ControlCenter.shared.currentControls()
            state = controls.contains { $0.kind == AppIdentifiers.ControlKind.capture } ? .added : .notAdded
        } catch {
            state = .unavailable
            if previous != .unavailable {
                log.error("control status unavailable: \(error.localizedDescription)")
            }
        }
        if state != previous { log.notice("control status \(previous) → \(state)") }
    }
}
