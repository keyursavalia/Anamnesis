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
        case capture
        case librarySamples
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink("Environment", value: Route.environment)
                    .accessibilityHint("Shows device, speech and screen-capture capabilities")
                #if canImport(ScreenCaptureKit)
                NavigationLink("SCK Probe", value: Route.sckProbe)
                    .accessibilityHint("Captures system audio with ScreenCaptureKit and records diagnostics")
                NavigationLink("Capture", value: Route.capture)
                    .accessibilityHint("Where the Control Center control lands; measures tap to first buffer")
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
                NavigationLink("Library samples", value: Route.librarySamples)
                    .accessibilityHint("Adds made-up poems and times the Library search")
                if let transcripts = environment.transcripts {
                    Section {
                        Toggle("Keep audio after transcription", isOn: Bindable(transcripts).keepsAudio)
                    } footer: {
                        Text("Captures: off follows D-010 (audio deleted once transcribed), as in Release.")
                    }
                }
            }
            .navigationTitle("Lab")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .environment: EnvironmentView()
                case .sckProbe: sckProbe
                case .sessions: SpoolSessionsView()
                case .transcription: TranscriptionLabView(model: environment.transcriptionLab())
                case .testB: EvalView(model: environment.evalLab())
                case .capture: capture
                case .librarySamples: LibrarySamplesView()
                }
            }
        }
        // A control/deep-link launch lands on the capture screen (spec 005).
        .onChange(of: environment.launchRequest?.id, initial: true) { _, id in
            guard id != nil, path.last != .capture else { return }
            path = [.capture]
        }
    }

    @ViewBuilder
    private var capture: some View {
        #if canImport(ScreenCaptureKit)
        CaptureLaunchView(model: environment.sckProbe())
        #else
        EmptyView()
        #endif
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
