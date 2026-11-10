import SwiftUI

struct RootView: View {
    var body: some View {
        #if DEBUG
        TabView {
            Tab("Lab", systemImage: "flask") {
                LabHomeView()
            }
        }
        #else
        // The product UI arrives after gates G1–G4 pass (ROADMAP); release builds show a placeholder until then.
        ContentUnavailableView("Anamnesis", systemImage: "text.quote", description: Text("Coming soon."))
        #endif
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment())
}
