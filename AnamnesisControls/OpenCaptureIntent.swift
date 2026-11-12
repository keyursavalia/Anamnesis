import AnamnesisKit
import AppIntents
import Foundation
import os

// SPIKE: spec 005. Member of BOTH the app and the controls extension: the control needs the types, and the system
// runs `perform` in the app (F-027). A returned `OpenURLIntent` with our own scheme is not delivered to the app
// (F-028), so `perform` posts to an in-process mailbox that `AppEnvironment` drains.

/// Rungs 1–2: brings the app forward on the capture screen. Discoverable so Shortcuts / Back Tap can run it too.
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
        CaptureLaunchLink.post(autoPresent ? .onArrival : .onTap)
        return .result()
    }
}

/// Rung 3: presents the picker over the current app when the app process can (suspended with a scene, F-030).
/// From a cold launch the picker would wait for the next app launch (F-031), so it falls back to rung 2.
struct CaptureInBackgroundIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture without opening"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    /// iOS 27: run in the app process (where the picker observer lives), never in the widget extension.
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    func perform() async throws -> some IntentResult {
        if await CaptureLaunchMailbox.shared.canPresentInPlace() {
            CaptureLaunchLink.post(.withoutForeground)
        } else {
            Logger(category: .ui).notice("rung 3: cannot present in place; continuing in foreground")
            // Post only once forward, so a declined hand-off leaves no request to fire on the next launch.
            try await continueInForeground(alwaysConfirm: false)
            CaptureLaunchLink.post(.onArrival)
        }
        return .result()
    }
}

private extension CaptureLaunchLink {
    nonisolated static func post(_ rung: Rung) {
        CaptureLaunchMailbox.shared.post(CaptureLaunchLink(rung: rung, tappedAt: Date()))
        Logger(category: .ui).notice("capture intent ran rung=\(rung.rawValue, privacy: .public)")
    }
}
