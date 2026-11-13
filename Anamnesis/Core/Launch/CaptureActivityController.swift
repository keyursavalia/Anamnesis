// `Activity` is not marked `Sendable`; each one is used by a single task here, looked up afresh, never shared.
@preconcurrency import ActivityKit
import AnamnesisKit
import Foundation

/// Drives the capture Live Activity (spec 007) from capture events, next to `CaptureControlSync`. The control's
/// intent starts it (`awaitingConsent`, R2); a capture started inside the app gets one at `started`. At most three
/// calls per capture: request, `listening`, end (R8). Every call is logged (R10); a failure never touches capture.
///
/// `Activity` is not `Sendable`, so the calls run off the main actor in one ordered chain (an update never overtakes
/// the end that follows it), each looking its activities up afresh.
final class CaptureActivityController {
    private typealias CaptureActivity = Activity<CaptureActivityAttributes>

    private let log: AppLog
    private var lastCall: Task<Void, Never>?

    init(log: AppLog) {
        self.log = log
    }

    /// R6: a killed process cannot end its activity. Takes the ids now, synchronously, so an activity the control's
    /// intent requests during this same cold launch is not ended with them. Only those still waiting or listening:
    /// an ended *saved* one keeps its 15 min on the Lock Screen (F-051).
    func endLeftovers() {
        let ids = Set(CaptureActivity.activities.filter(\.content.state.isActive).map(\.id))
        guard !ids.isEmpty else { return }
        log.notice("activity: ending \(ids.count) left over from an earlier process")
        enqueue { log in
            for activity in CaptureActivity.activities where ids.contains(activity.id) {
                await Self.end(activity, with: nil, dismissal: .immediate, log: log)
            }
        }
    }

    /// Updates the activity the intent started, ending any extras (R6), or requests one for an in-app start.
    func captureStarted(at startedAt: Date, sessionID: String?) {
        let state = CaptureActivityState.listening(since: startedAt, sessionID: sessionID)
        enqueue { log in
            let current = CaptureActivity.activities
            guard let kept = current.last else {
                Self.request(state, log: log)
                return
            }
            for extra in current.dropLast() { await Self.end(extra, with: nil, dismissal: .immediate, log: log) }
            await kept.update(ActivityContent(state: state, staleDate: nil))
            log.notice("activity updated id=\(kept.id) phase=\(state.phase.rawValue) "
                       + "activityState=\(String(describing: kept.activityState))")
        }
    }

    /// Picker cancelled or failed, the stream did not start, or the activity is stale: nothing to show (R6).
    func endAll(reason: String) {
        enqueue { log in
            let current = CaptureActivity.activities
            guard !current.isEmpty else { return }
            log.notice("activity: ending all (\(reason))")
            for activity in current { await Self.end(activity, with: nil, dismissal: .immediate, log: log) }
        }
    }

    /// Any stop, including from the recording indicator (R3): `saved` for 15 min, or `failed` and gone (R6).
    func captureStopped(sessionID: String?, capturedSeconds: Double) {
        let state = CaptureActivityState.stopped(sessionID: sessionID, capturedSeconds: capturedSeconds)
        let dismissal: ActivityUIDismissalPolicy = state.dismissalDelay > 0
            ? .after(Date().addingTimeInterval(state.dismissalDelay)) : .immediate
        enqueue { log in
            let current = CaptureActivity.activities
            guard !current.isEmpty else {
                log.notice("activity: none to end at stop")
                return
            }
            for activity in current {
                await Self.end(activity, with: ActivityContent(state: state, staleDate: nil), dismissal: dismissal,
                               log: log)
            }
        }
    }

    // MARK: - ActivityKit calls

    private func enqueue(_ call: @escaping @Sendable (AppLog) async -> Void) {
        let previous = lastCall
        let log = log
        lastCall = Task.detached {
            await previous?.value
            await call(log)
        }
    }

    private nonisolated static func request(_ state: CaptureActivityState, log: AppLog) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.notice("activity not requested: Live Activities are off")
            return
        }
        do {
            let activity = try Activity.request(
                attributes: CaptureActivityAttributes(), content: ActivityContent(state: state, staleDate: nil))
            log.notice("activity requested id=\(activity.id) phase=\(state.phase.rawValue)")
        } catch {
            log.error("activity request failed phase=\(state.phase.rawValue): \(error.localizedDescription)")
        }
    }

    private nonisolated static func end(
        _ activity: CaptureActivity, with content: ActivityContent<CaptureActivityState>?,
        dismissal: ActivityUIDismissalPolicy, log: AppLog
    ) async {
        await activity.end(content, dismissalPolicy: dismissal)
        log.notice("activity ended id=\(activity.id) phase=\(content?.state.phase.rawValue ?? "unchanged") "
                   + "activityState=\(String(describing: activity.activityState))")
    }
}
