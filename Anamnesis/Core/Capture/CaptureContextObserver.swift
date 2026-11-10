import AnamnesisKit
import AVFAudio
import UIKit

// SPIKE: while capturing, writes system events into the report as `note` markers so a sudden change in the
// captured audio (F-016: digital silence while a reel was audible) can be lined up with what the OS did.
// Only observes; changes no session or app state.
nonisolated final class CaptureContextObserver {
    private var tokens: [any NSObjectProtocol] = []

    init(recorder: DiagnosticsRecorder) {
        let center = NotificationCenter.default
        let events: [(Notification.Name, @Sendable (Notification) -> String)] = [
            // iOS 27 replacements for the deprecated interruption notification (APPLE_APIS ledger).
            (AVAudioSession.didBecomeInactiveNotification, { _ in "audio: session became inactive" }),
            (AVAudioSession.resumptionRecommendationNotification, { _ in "audio: resumption recommendation" }),
            (AVAudioSession.routeChangeNotification, Self.describeRouteChange),
            (AVAudioSession.mediaServicesWereLostNotification, { _ in "audio: media services lost" }),
            (AVAudioSession.mediaServicesWereResetNotification, { _ in "audio: media services reset" }),
            (AVAudioSession.silenceSecondaryAudioHintNotification, Self.describeSilenceHint),
            (UIApplication.didEnterBackgroundNotification, { _ in "app: background" }),
            (UIApplication.willEnterForegroundNotification, { _ in "app: foreground" }),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, { _ in "device: locking" }),
            (UIApplication.didReceiveMemoryWarningNotification, { _ in "app: memory warning" })
        ]
        // `queue: nil`: the block runs on the posting thread; the recorder is thread-safe and the work is O(1).
        tokens = events.map { name, describe in
            center.addObserver(forName: name, object: nil, queue: nil) { notification in
                recorder.addMarker(.note, text: describe(notification))
            }
        }
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    private static func describeRouteChange(_ notification: Notification) -> String {
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
        return "audio: route change reason=\(raw) outputs=\(outputs)"
    }

    private static func describeSilenceHint(_ notification: Notification) -> String {
        let raw = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt ?? 0
        return "audio: other audio \(raw == 1 ? "began" : "ended") (secondary-audio hint)"
    }
}
