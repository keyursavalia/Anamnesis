import AnamnesisKit
import AppIntents
import Foundation
import os

// Spec 005. Member of BOTH the app and the controls extension: the control needs the types, and the system runs
// `perform` in the app (F-027). A returned `OpenURLIntent` with our own scheme is not delivered to the app (F-028),
// so `perform` posts to an in-process mailbox that `AppEnvironment` drains.

/// The *Capture poem* toggle. On: presents the picker over the current app without bringing Anamnesis forward,
/// cold, windowless or suspended (rung 3, F-036). Off: stops the capture. The app acts on the real capture state, so a
/// tap on a switch left stale by a stop from the recording indicator still does what the user means (F-037).
struct CaptureToggleIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Capture poem"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    /// iOS 27: run in the app process (where the picker observer lives), never in the widget extension.
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Capturing")
    var value: Bool

    func perform() async throws -> some IntentResult {
        CaptureLaunchMailbox.post(value ? .start(CaptureLaunchLink(rung: .withoutForeground, tappedAt: Date())) : .stop)
        return .result()
    }
}

/// Rungs 1–2: brings the app forward on the capture screen. Discoverable so Shortcuts / Back Tap can run it.
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open capture"
    static let description = IntentDescription("Opens Anamnesis on the capture screen.")
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
