import AnamnesisKit
import WidgetKit

/// Mirrors the capture state to the *Capture poem* control (spec 005 Step 6): writes it to the App Group, where
/// the control's value provider reads it, and asks the system to reload the control.
///
/// The system honours a reload only while the app is in front or within ~2.5 s of the control's own intent; one from
/// the background on the app's own initiative, e.g. after a stop from the recording indicator, is dropped, and
/// retrying later does not help (F-037). The intent therefore acts on the real capture state, not the switch value.
enum CaptureControlSync {
    static func publish(_ state: CaptureControlState, log: AppLog) {
        guard let url = CaptureControlState.sharedURL else {
            log.error("control state not written: App Group \(AppIdentifiers.appGroupID) unavailable")
            return
        }
        do {
            try state.write(to: url)
        } catch {
            log.error("control state not written: \(error.localizedDescription)")
            return
        }
        log.notice("control state isCapturing=\(state.isCapturing)")
        reload(log: log)
    }

    static func reload(log: AppLog) {
        ControlCenter.shared.reloadControls(ofKind: AppIdentifiers.ControlKind.capture)
        log.notice("control reload requested")
    }
}
