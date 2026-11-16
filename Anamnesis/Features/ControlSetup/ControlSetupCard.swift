import SwiftUI
import TipKit

/// The Transcribe screen's setup area (spec 015 R9; TipKit since spec 020 R10, D-038). While *Transcribe* is not
/// placed, the Control Center tip invites the user (*Show me how* opens the guide; closing it retires it). On iPhone,
/// after a few launches, the Action Button tip follows. TipKit spaces them a week apart. Once the control appears
/// after the user was asked, it says so once, then never again.
struct ControlSetupCard: View {
    @Environment(AppEnvironment.self) private var environment
    /// "Later" on the pre-TipKit card: honoured by retiring the tip.
    @AppStorage("tip.controlCenter.dismissed") private var dismissed = false
    /// The user has seen the tip asking; only then is "added" news worth a card.
    @AppStorage("controlSetup.sawNotAdded") private var sawNotAdded = false
    @AppStorage("controlSetup.celebrated") private var celebrated = false
    @State private var showsGuide = false
    private let controlTip = ControlCenterTip()
    private let actionButtonTip = ActionButtonTip()

    var body: some View {
        // No spacing: a tip that is not showing takes no room, and each card brings its own margin.
        VStack(spacing: 0) {
            if environment.controlCenter.state == .added {
                if sawNotAdded && !celebrated { added.transition(.scale(scale: 0.95).combined(with: .opacity)) }
            } else if environment.controlCenter.state != .unknown {
                TipView(controlTip) { action in
                    if action.id == ControlCenterTip.showGuide { showsGuide = true }
                }
                .onAppear { sawNotAdded = true }
            }
            TipView(actionButtonTip)
        }
        .tipViewStyle(CardTipStyle())
        // The style draws its own card; TipKit's plate behind it would double it.
        .tipBackground(Color.clear)
        .tipCornerRadius(Theme.cornerRadius)
        .animation(.smooth, value: environment.controlCenter.state)
        .sensoryFeedback(.success, trigger: environment.controlCenter.isAdded) { _, added in added && sawNotAdded }
        .sheet(isPresented: $showsGuide) { ControlSetupSheet() }
        .task {
            if dismissed { controlTip.invalidate(reason: .tipClosed) }
        }
    }

    private var added: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(Theme.sage)
                .symbolEffect(.bounce, options: .nonRepeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribe is ready").font(.headline)
                Text("Swipe down and tap it whenever something’s worth keeping.")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
            Button("Done") { withAnimation(.smooth) { celebrated = true } }
                .buttonStyle(QuietButtonStyle())
        }
        .card(padding: 16)
    }
}
