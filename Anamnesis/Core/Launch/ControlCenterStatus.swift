import AnamnesisKit
import Observation
import WidgetKit

/// Whether the user has added the *Transcribe* control (spec 015 R9). iOS has no API to add a control for the
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
    @ObservationIgnored private var followUp: Task<Void, Never>?

    init(log: AppLog) {
        self.log = log
    }

    var isAdded: Bool { state == .added }

    /// The app is in front again, often straight from editing Control Center. The edit is saved as Control Center
    /// closes, which can be after the app is already active, so a single query then still saw a removed control as
    /// placed. Asks again a moment later, and once more after that.
    func refreshAfterReturning() {
        followUp?.cancel()
        followUp = Task { [weak self] in
            for delay in [0.0, 1.5, 4.0] {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, let self else { return }
                await refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previous = state
        do {
            let controls = try await ControlCenter.shared.currentControls()
            state = controls.contains { $0.kind == AppIdentifiers.ControlKind.capture } ? .added : .notAdded
            // Placement detection is a device finding (APPLE_APIS.md): log what WidgetKit reported with each change.
            if state != previous {
                log.notice("control query returned \(controls.count) control(s): \(controls.map(\.kind))")
            }
        } catch {
            state = .unavailable
            if previous != .unavailable {
                log.error("control status unavailable: \(error.localizedDescription)")
            }
        }
        if state != previous { log.notice("control status \(previous) → \(state)") }
        AppTips.controlStatusChanged(state)
    }
}
