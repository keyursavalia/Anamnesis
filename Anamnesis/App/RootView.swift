import AnamnesisKit
import SwiftData
import SwiftUI

/// Listen, Library and Settings in every build (spec 015 R1); DEBUG adds the Lab (D-014). The welcome shows once.
/// No badge since spec 016: there is nothing left to review.
struct RootView: View {
    enum TabID: Hashable {
        case listen
        case library
        case settings
        case lab
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var tab = TabID.listen
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    /// The Control Center guide, offered once right after the welcome (spec 015 R9).
    @State private var showsControlSetup = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Listen", systemImage: "waveform", value: TabID.listen) {
                ListenView { tab = .library }
            }
            Tab("Library", systemImage: "books.vertical", value: TabID.library) {
                LibraryView { tab = .listen }
            }
            Tab("Settings", systemImage: "gearshape", value: TabID.settings) {
                SettingsView()
            }
            #if DEBUG
            Tab("Lab", systemImage: "flask", value: TabID.lab) {
                LabHomeView()
            }
            #endif
        }
        .tint(Theme.ember)
        .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { onboardingCompleted = !$0 }),
                         onDismiss: offerControlSetup) {
            OnboardingView { onboardingCompleted = true }
        }
        .sheet(isPresented: $showsControlSetup) { ControlSetupSheet() }
        .onChange(of: environment.openSessionID) { _, id in
            if id != nil { tab = .listen }
        }
        .onChange(of: environment.dataDeletedAt) { tab = .listen }
        #if DEBUG
        // DEBUG keeps the spec 005 flow: rungs 1–2 land on Lab → Capture. Rung 3 never leaves the current screen.
        .onChange(of: environment.launchRequest?.id) {
            guard let request = environment.launchRequest, request.link.rung != .withoutForeground else { return }
            tab = .lab
        }
        #endif
    }

    private func offerControlSetup() {
        Task {
            await environment.controlCenter.refresh()
            if !environment.controlCenter.isAdded { showsControlSetup = true }
        }
    }
}

#Preview {
    let environment = AppEnvironment()
    RootView()
        .environment(environment)
        .modelContainer(environment.library.container)
}
