import SwiftUI

/// The Listen screen's setup card (spec 015 R9). Shown only while *Transcribe* is not placed and the user has not
/// chosen Later; once the control appears it says so once, then never shows again.
struct ControlSetupCard: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("tip.controlCenter.dismissed") private var dismissed = false
    /// The user has seen the card asking; only then is "added" news worth a card.
    @AppStorage("controlSetup.sawNotAdded") private var sawNotAdded = false
    @AppStorage("controlSetup.celebrated") private var celebrated = false
    @State private var showsGuide = false

    var body: some View {
        Group {
            switch environment.controlCenter.state {
            case .unknown:
                EmptyView()
            case .added:
                if sawNotAdded && !celebrated { added.transition(.scale(scale: 0.95).combined(with: .opacity)) }
            case .notAdded, .unavailable:
                if !dismissed { invite.onAppear { sawNotAdded = true } }
            }
        }
        .animation(.smooth, value: environment.controlCenter.state)
        .sensoryFeedback(.success, trigger: environment.controlCenter.isAdded) { _, added in added && sawNotAdded }
        .sheet(isPresented: $showsGuide) { ControlSetupSheet() }
    }

    private var invite: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "switch.2")
                    .font(.title2)
                    .foregroundStyle(Theme.ember)
                    .frame(width: 44, height: 44)
                    .background(Theme.ember.opacity(0.12), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcribe from any app").font(.headline)
                    Text("Add **Transcribe** to Control Center and start without leaving your reel.")
                        .font(.footnote).foregroundStyle(Theme.inkSecondary)
                }
            }
            // Two equal halves across the card, so neither button looks like an afterthought.
            HStack(spacing: 10) {
                Button { showsGuide = true } label: {
                    Label("Show me how", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(ProminentButtonStyle())
                Button { withAnimation(.smooth) { dismissed = true } } label: {
                    Text("Later").frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityHint("Hides this card. The guide stays in Settings.")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .card(padding: 16)
    }

    private var added: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(Theme.sage)
                .symbolEffect(.bounce, options: .nonRepeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribe is ready").font(.headline)
                Text("Swipe down and tap it when a poem starts.")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
            Button("Done") { withAnimation(.smooth) { celebrated = true } }
                .buttonStyle(QuietButtonStyle())
        }
        .card(padding: 16)
    }
}
