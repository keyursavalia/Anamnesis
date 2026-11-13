import AnamnesisKit
import SwiftData
import SwiftUI

/// Captures in every build (spec 008 R2); DEBUG adds the Lab (D-014).
struct RootView: View {
    enum TabID: Hashable {
        case captures
        case library
        case settings
        case lab
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var tab = TabID.captures
    /// Moments waiting for Save or Dismiss, across sessions (spec 010 R3).
    @Query(filter: #Predicate<MomentRecord> { $0.reviewRaw == "new" }) private var newMoments: [MomentRecord]

    var body: some View {
        TabView(selection: $tab) {
            Tab("Captures", systemImage: "waveform", value: TabID.captures) {
                CapturesView()
            }
            .badge(newMoments.count)
            Tab("Library", systemImage: "books.vertical", value: TabID.library) {
                LibraryView()
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
        .onChange(of: environment.openSessionID) { _, id in
            if id != nil { tab = .captures }
        }
        .onChange(of: environment.dataDeletedAt) { tab = .captures }
        #if DEBUG
        // DEBUG keeps the spec 005 flow: rungs 1–2 land on Lab → Capture. Rung 3 never leaves the current screen.
        .onChange(of: environment.launchRequest?.id) {
            guard let request = environment.launchRequest, request.link.rung != .withoutForeground else { return }
            tab = .lab
        }
        #endif
    }
}

#Preview {
    let environment = AppEnvironment()
    RootView()
        .environment(environment)
        .modelContainer(environment.library.container)
}
