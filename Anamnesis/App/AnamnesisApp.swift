import SwiftUI

@main
struct AnamnesisApp: App {
    /// Not `@State`: its initial value is evaluated lazily, which a cold background launch for an intent may not
    /// reach before `perform` runs (F-032).
    private let environment = AppEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                // Covers launch too: the first phase change is to `.active`.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    environment.drainLaunchMailbox()
                    environment.reloadControl()
                    Task { await environment.refreshSessions() }
                }
                .onOpenURL { environment.open($0) }
        }
    }
}
