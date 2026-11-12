import AnamnesisKit
import AppIntents
import SwiftUI
import WidgetKit

// SPIKE: spec 005 launch-trigger ladder. Two controls so both rungs can sit in Control Center side by side.

/// Rung 2: opens the app and presents the screen-sharing picker on arrival.
struct CapturePoemControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppIdentifiers.ControlKind.capture) {
            ControlWidgetButton(action: OpenCaptureIntent(autoPresent: true)) {
                Label("Capture poem", systemImage: "text.quote")
            }
        }
        .displayName("Capture poem")
        .description("Opens Anamnesis and asks to share this device's audio.")
    }
}

/// Rung 1: opens the app on the capture screen; one more tap presents the picker.
struct OpenCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppIdentifiers.ControlKind.openCapture) {
            ControlWidgetButton(action: OpenCaptureIntent(autoPresent: false)) {
                Label("Open capture", systemImage: "record.circle")
            }
        }
        .displayName("Open capture")
        .description("Opens Anamnesis on the capture screen.")
    }
}

/// Rung 3 (experiment): asks for the picker while you stay in the current app.
struct CaptureHereControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppIdentifiers.ControlKind.captureHere) {
            ControlWidgetButton(action: CaptureInBackgroundIntent()) {
                Label("Capture here", systemImage: "waveform")
            }
        }
        .displayName("Capture here (test)")
        .description("Experiment: asks to share audio without opening Anamnesis.")
    }
}
