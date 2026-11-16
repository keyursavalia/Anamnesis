// `Activity` is not marked `Sendable`; each one is used by a single task here, looked up afresh, never shared.
@preconcurrency import ActivityKit
import AnamnesisKit
import Foundation

/// Drives the capture Live Activity (spec 007) from capture events, next to `CaptureControlSync`. The control's
/// intent starts it (`awaitingConsent`, R2); a capture started inside the app gets one at `started`. At most three
/// calls per capture: request, `listening`, end (R8), plus one alert update when a stop from outside the app is
/// announced (spec 018). Every call is logged (R10); a failure never touches capture.
///
/// `Activity` is not `Sendable`, so the calls run off the main actor in one ordered chain (an update never overtakes
/// the end that follows it), each looking its activities up afresh.
final class CaptureActivityController {
    private typealias CaptureActivity = Activity<CaptureActivityAttributes>

    private let log: AppLog
    private var lastCall: Task<Void, Never>?
    /// The announced card's wait before the end (spec 018); cancelled when the app comes forward.
    private var announceHold: Task<Void, Never>?

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
            await kept.update(ActivityContent(state: state, staleDate: state.staleDate(from: Date())))
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

    /// The app is in front, so a saved or failed activity has done its job. Tapping a Live Activity only opens the
    /// app (its `widgetURL`), it never dismisses it: without this the saved card stayed up for its 15 min. Cuts an
    /// announcement short; an activity still waiting or listening is kept.
    func dismissFinished() {
        announceHold?.cancel()
        enqueue { log in
            let finished = CaptureActivity.activities.filter { !$0.content.state.isActive }
            guard !finished.isEmpty else { return }
            log.notice("activity: dismissing \(finished.count) finished (app in front)")
            for activity in finished { await Self.end(activity, with: nil, dismissal: .immediate, log: log) }
        }
    }

    /// Any stop, including from the recording indicator (R3). Stopped from outside the app, `saved` stays on the Lock
    /// Screen for 15 min (or until the app comes forward, `dismissFinished`); otherwise it is gone at once (R6).
    ///
    /// `announce` (spec 018, owner: "like Shazam"): when the stop came from outside the app, a saved capture is first
    /// updated with an alert, so the Dynamic Island expands into the *Poem captured · Open* card (a banner on
    /// iPhones without one), and ended `announceSeconds` later; `end` cannot carry an alert, and ending at once would
    /// cut the card short. A background task keeps the process alive for that wait. With the app in front there is
    /// nothing to announce: the activity ends and is dismissed at once.
    func captureStopped(sessionID: String?, capturedSeconds: Double, announce: Bool) {
        let state = CaptureActivityState.stopped(sessionID: sessionID, capturedSeconds: capturedSeconds)
        let dismissal: ActivityUIDismissalPolicy = announce && state.dismissalDelay > 0
            ? .after(Date().addingTimeInterval(state.dismissalDelay)) : .immediate
        let alert = announce && state.phase == .saved ? Self.announcement(for: state) : nil
        let hold: Task<Void, Never>? = alert.map { _ in
            Task { _ = try? await Task.sleep(for: .seconds(Self.announceSeconds)) }
        }
        announceHold = hold
        // Ended by the chain well inside the ~30 s the system grants; ended at expiry too, should the chain stall.
        let keepAlive = alert.map { _ in BackgroundTask(name: "activity-announce", log: log) }
        enqueue { log in
            let current = CaptureActivity.activities
            if current.isEmpty { log.notice("activity: none to end at stop") }
            let content = ActivityContent(state: state, staleDate: nil)
            if let alert, !current.isEmpty {
                for activity in current { await activity.update(content, alertConfiguration: alert) }
                log.notice("activity announced saved capture (\(state.formattedDuration ?? "?"))")
                await hold?.value
            }
            for activity in current {
                await Self.end(activity, with: content, dismissal: dismissal, log: log)
            }
            if let keepAlive { await keepAlive.end() }
        }
    }

    /// How long the expanded card stays in the island before the activity ends (the Lock Screen keeps it 15 min).
    static let announceSeconds = 8.0

    /// The banner on iPhones without a Dynamic Island; on those with one, the island shows the expanded view.
    private static func announcement(for state: CaptureActivityState) -> AlertConfiguration {
        AlertConfiguration(title: "Ready to transcribe",
                           body: "Open Anamnesis to transcribe it into your Library.",
                           sound: .default)
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
                attributes: CaptureActivityAttributes(),
                content: ActivityContent(state: state, staleDate: state.staleDate(from: Date())))
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
