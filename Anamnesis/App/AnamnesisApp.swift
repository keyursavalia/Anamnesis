import SwiftData
import SwiftUI

@main
struct AnamnesisApp: App {
    /// Not `@State`: its initial value is evaluated lazily, which a cold background launch for an intent may not
    /// reach before `perform` runs (F-032).
    private let environment = AppEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyAppearance()
        AppTips.configure()
        #if DEBUG
        ScreenshotScene.prepareLaunch()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                // Covers launch too: the first phase change is to `.active`.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    environment.drainLaunchMailbox()
                    environment.capture.sceneBecameActive()
                    environment.capture.activity.dismissFinished()
                    environment.reloadControl()
                    Task { await environment.refreshSessions() }
                    environment.controlCenter.refreshAfterReturning()
                    AppTips.appBecameActive()
                    // A new user's speech model, or one an offline first launch could not fetch (spec 020 R7).
                    Task { await environment.transcripts?.prepareModel() }
                }
                .onOpenURL { environment.open($0) }
                .modelContainer(environment.library.container)
        }
    }
}
