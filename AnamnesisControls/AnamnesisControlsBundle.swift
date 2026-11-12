import SwiftUI
import WidgetKit

@main
struct AnamnesisControlsBundle: WidgetBundle {
    var body: some Widget {
        CapturePoemControl()
        OpenCaptureControl()
        CaptureHereControl()
    }
}
