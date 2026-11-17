import SwiftUI

/// Settings (spec 013; restructured in spec 016 R10–R12): the brand row (opens About), two cards for the guide and
/// the *Transcribe* control, then App settings, Privacy and Terms of Use.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsGuide = false
    @State private var showsControlSetup = false
    #if DEBUG
    @State private var showsScreenshotPrivacy = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AboutView() } label: { brandRow }
                }
                .listRowBackground(Theme.surface)

                Section {
                    tiles
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSpacing(16)

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
            #if DEBUG
            // SPIKE: App Store screenshots.
            .navigationDestination(isPresented: $showsScreenshotPrivacy) { PrivacyView() }
            .task { showsScreenshotPrivacy = ScreenshotScene.current == .privacy }
            #endif
        }
    }

    private var brandRow: some View {
        HStack(spacing: 16) {
            AppMark(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Anamnesis").font(Theme.display(.title2)).foregroundStyle(Theme.ink)
                Text("Transcribe anything you hear.").font(Theme.verse(.subheadline)).italic()
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint("About Anamnesis")
    }

    /// Spec 016 R10: two cards side by side under the app name, as tall as the taller one's text.
    private var tiles: some View {
        let added = environment.controlCenter.isAdded
        return HStack(alignment: .top, spacing: 12) {
            ActionTile(title: "How it works", detail: "The welcome, again", systemImage: "sparkles",
                       tint: Theme.ember) { showsGuide = true }
            ActionTile(title: "Control Center",
                       detail: added ? "Transcribe is ready to tap" : "Add Transcribe in a few taps",
                       systemImage: added ? "checkmark.circle.fill" : "switch.2",
                       tint: added ? Theme.sage : Theme.ember) { showsControlSetup = true }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A card button: icon badge and a chevron across the top, then the title and a short status. Fills the height its
/// row gives it, so two side by side match.
private struct ActionTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 42, height: 42)
                        .background(tint.opacity(0.13), in: .rect(cornerRadius: 12, style: .continuous))
                        .contentTransition(.symbolEffect(.replace))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(detail).font(.footnote).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
            .contentShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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
