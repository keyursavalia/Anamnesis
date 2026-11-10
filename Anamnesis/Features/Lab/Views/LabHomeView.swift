#if DEBUG
import SwiftUI

// SPIKE: Lab entry point; later specs add probe, import and WER screens here.
struct LabHomeView: View {
    enum Route: Hashable {
        case environment
    }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Environment", value: Route.environment)
                    .accessibilityHint("Shows device, speech and screen-capture capabilities")
            }
            .navigationTitle("Lab")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .environment: EnvironmentView()
                }
            }
        }
    }
}

#Preview {
    LabHomeView()
}
#endif
