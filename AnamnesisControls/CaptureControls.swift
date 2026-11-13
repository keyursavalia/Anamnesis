import AnamnesisKit
import AppIntents
import SwiftUI
import WidgetKit

/// The one-tap trigger (spec 005 Step 6): on presents the screen-sharing picker over the current app (rung 3),
/// off stops the capture. The app mirrors the real capture state into the App Group, so the toggle flips back off
/// after a cancelled picker or a stop from the system indicator.
struct CapturePoemControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppIdentifiers.ControlKind.capture, provider: CaptureStateProvider()) { isOn in
            ControlWidgetToggle(isOn: isOn, action: CaptureToggleIntent()) {
                Label("Capture poem", systemImage: "text.quote")
            } valueLabel: { isOn in
                Text(isOn ? "Listening" : "Off")
            }
        }
        .displayName("Capture poem")
        .description("Captures the audio playing on this device without leaving the app you are in.")
    }
}

/// Runs in the widget extension; reads what the app last wrote.
struct CaptureStateProvider: ControlValueProvider {
    let previewValue = false

    func currentValue() async throws -> Bool {
        (CaptureControlState.sharedURL.map(CaptureControlState.init(contentsOf:)) ?? .idle).isCapturing
    }
}
