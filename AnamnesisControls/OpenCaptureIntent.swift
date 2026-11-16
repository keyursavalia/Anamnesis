// `Activity` is not marked `Sendable`; each one is used by a single task here, looked up afresh, never shared.
@preconcurrency import ActivityKit
import AnamnesisKit
import AppIntents
import Foundation
import os

// Spec 005. Member of BOTH the app and the controls extension: the control needs the types, and the system runs
// `perform` in the app (F-027). A returned `OpenURLIntent` with our own scheme is not delivered to the app (F-028),
// so `perform` posts to an in-process mailbox that `AppEnvironment` drains.

/// The *Transcribe* toggle. On: presents the picker over the current app without bringing Anamnesis forward,
/// cold, windowless or suspended (rung 3, F-036). Off: stops the capture. The app acts on the real capture state, so a
/// tap on a switch left stale by a stop from the recording indicator still does what the user means (F-037).
/// A `LiveActivityIntent` too, so `perform` may start the capture Live Activity without the app in front (spec 007).
struct CaptureToggleIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Transcribe"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    /// iOS 27: run in the app process (where the picker observer lives), never in the widget extension.
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Listening")
    var value: Bool

    func perform() async throws -> some IntentResult {
        if value { await CaptureActivityStart.awaitConsent() }
        CaptureLaunchMailbox.post(value ? .start(CaptureLaunchLink(rung: .withoutForeground, tappedAt: Date())) : .stop)
        return .result()
    }
}

/// The Live Activity's Stop button (spec 007 R4). Runs in the app like the toggle, so the control reload that
/// follows the stop is honoured and the switch turns off at once (F-037).
struct StopCaptureIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Listening"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    func perform() async throws -> some IntentResult {
        CaptureLaunchMailbox.post(.stopIfCapturing)
        return .result()
    }
}

/// Starts the activity inside the toggle's `perform`, the window in which the system allows it without the app in
/// front (R2). The app takes it over from there (`CaptureActivityController`). Never fails the intent (§4.4).
private enum CaptureActivityStart {
    static func awaitConsent() async {
        let log = Logger(category: .ui)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.notice("activity not requested: Live Activities are off")
            return
        }
        let existing = Activity<CaptureActivityAttributes>.activities
        // Listening already: the switch showed a stale "off" during a capture; the app keeps that capture (F-037).
        if existing.contains(where: { $0.content.state.phase == .listening }) {
            log.notice("activity kept: a capture is listening")
            return
        }
        // At most one activity (R6).
        for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
        do {
            let activity = try Activity.request(
                attributes: CaptureActivityAttributes(),
                content: ActivityContent(state: .awaitingConsent,
                                         staleDate: CaptureActivityState.awaitingConsent.staleDate(from: Date())))
            log.notice("activity requested id=\(activity.id, privacy: .public) phase=awaitingConsent")
        } catch {
            log.error("activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Rungs 1–2: brings the app forward on the capture screen. Discoverable so Shortcuts / Back Tap can run it.
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Transcribe"
    static let description = IntentDescription("Opens Anamnesis on the Transcribe screen, ready to start.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Present picker", default: false)
    var autoPresent: Bool

    init() {}

    init(autoPresent: Bool) {
        self.autoPresent = autoPresent
    }

    /// Runs in the app after launch, so `tappedAt` is when the intent ran, not the tap itself (cold-launch time
    /// before it is not included).
    func perform() async throws -> some IntentResult {
        CaptureLaunchMailbox.post(.start(CaptureLaunchLink(rung: autoPresent ? .onArrival : .onTap, tappedAt: Date())))
        return .result()
    }
}

private extension CaptureLaunchMailbox {
    nonisolated static func post(_ command: Command) {
        shared.post(command)
        Logger(category: .ui).notice("capture intent ran command=\(String(describing: command), privacy: .public)")
    }
}
