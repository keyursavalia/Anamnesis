import SwiftUI

/// Settings (spec 013; restructured in spec 016 R10–R12): the brand row (opens About), two square tiles for the guide
/// and the *Capture poem* control, then App settings, Privacy and Terms of Use.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsGuide = false
    @State private var showsControlSetup = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AboutView() } label: { brandRow }
                }
                .listRowBackground(Theme.surface)

                tiles
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                Section {
                    NavigationLink { AppSettingsView() } label: {
                        SettingsRow(title: "App settings", systemImage: "gearshape.fill", tint: Theme.inkSecondary)
                    }
                    NavigationLink { PrivacyView() } label: {
                        SettingsRow(title: "Privacy", systemImage: "hand.raised.fill", tint: Theme.sage)
                    }
                    NavigationLink { TermsView() } label: {
                        SettingsRow(title: "Terms of Use", systemImage: "doc.text.fill", tint: Theme.ember)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .paperBackground()
            .tint(Theme.ember)
            .navigationTitle("Settings")
            .sheet(isPresented: $showsGuide) { OnboardingView { showsGuide = false } }
            .sheet(isPresented: $showsControlSetup) { ControlSetupSheet() }
            .task { await environment.controlCenter.refresh() }
        }
    }

    private var brandRow: some View {
        HStack(spacing: 16) {
            AppMark(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Anamnesis").font(Theme.display(.title2)).foregroundStyle(Theme.ink)
                Text("Keep the poems you hear.").font(Theme.verse(.subheadline)).italic()
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint("About Anamnesis")
    }

    /// Spec 016 R10: two squares side by side under the app name.
    private var tiles: some View {
        let added = environment.controlCenter.isAdded
        return HStack(spacing: 12) {
            SquareTile(title: "How it works", detail: "The three steps, again", systemImage: "sparkles",
                       tint: Theme.ember) { showsGuide = true }
            SquareTile(title: "Capture poem", detail: added ? "In Control Center" : "Add to Control Center",
                       systemImage: added ? "checkmark.circle.fill" : "switch.2",
                       tint: added ? Theme.sage : Theme.ember) { showsControlSetup = true }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

/// A square button: icon top-left, title and a short status bottom-left.
private struct SquareTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // A square base with the content laid over it, so the tile stays square at any width.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: systemImage)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(tint)
                            .frame(width: 48, height: 48)
                            .background(tint.opacity(0.13), in: .rect(cornerRadius: 14, style: .continuous))
                            .contentTransition(.symbolEffect(.replace))
                        Spacer(minLength: 8)
                        Text(title).font(.headline).foregroundStyle(Theme.ink)
                        Text(detail).font(.footnote).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                }
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

/// A Settings row: a coloured icon tile and a title.
struct SettingsRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title).foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: .rect(cornerRadius: 7, style: .continuous))
        }
    }
}
