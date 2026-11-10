import SwiftUI

@main
struct AnamnesisApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                // Covers launch too: the first phase change is to `.active`.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    Task { await environment.refreshSessions() }
                }
        }
    }
}
