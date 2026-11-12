#if DEBUG
import SwiftUI

// SPIKE: Lab entry point; later specs add probe, import and WER screens here.
struct LabHomeView: View {
    enum Route: Hashable {
        case environment
        case sckProbe
        case sessions
        case transcription
        case testB
    }

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Environment", value: Route.environment)
                    .accessibilityHint("Shows device, speech and screen-capture capabilities")
                #if canImport(ScreenCaptureKit)
                NavigationLink("SCK Probe", value: Route.sckProbe)
                    .accessibilityHint("Captures system audio with ScreenCaptureKit and records diagnostics")
                #else
                Text("SCK Probe (device only: no ScreenCaptureKit in this SDK)")
                    .foregroundStyle(.secondary)
                #endif
                NavigationLink("Spool sessions", value: Route.sessions)
                    .accessibilityHint("Lists spooled capture sessions for playback, export and deletion")
                NavigationLink("Transcription", value: Route.transcription)
                    .accessibilityHint("Installs the speech model and transcribes imported audio on device")
                NavigationLink("Test B", value: Route.testB)
                    .accessibilityHint("Runs the transcript-quality corpus and scores word error rate")
            }
            .navigationTitle("Lab")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .environment: EnvironmentView()
                case .sckProbe: sckProbe
                case .sessions: SpoolSessionsView()
                case .transcription: TranscriptionLabView(model: environment.transcriptionLab())
                case .testB: EvalView(model: environment.evalLab())
                }
            }
        }
    }

    @ViewBuilder
    private var sckProbe: some View {
        #if canImport(ScreenCaptureKit)
        SCKProbeView(model: environment.sckProbe())
        #else
        EmptyView()
        #endif
    }
}

#Preview {
    LabHomeView()
        .environment(AppEnvironment())
}
#endif
