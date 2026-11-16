import SwiftUI

/// "Transcribe from any app" (spec 015 R9): shown right after the welcome and from Settings. While it is open it
/// re-checks every 1.5 s, because Control Center opens over the app without backgrounding it; the moment the
/// control is placed the guide turns into a "You're set" screen.
struct ControlSetupSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = environment.controlCenter.state
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if state == .added {
                        AddedView()
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        header
                        ControlSetupGuide().card()
                        Text("""
                            You can also put **Transcribe** on the Lock Screen, or on the Action Button \
                            (Settings → Action Button → Controls).
                            """)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { footer(state) }
            .paperBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .animation(.spring(duration: 0.5, bounce: 0.3), value: state)
        }
        .sensoryFeedback(.success, trigger: state == .added)
        .task {
            while !Task.isCancelled {
                await environment.controlCenter.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "switch.2")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.ember)
                .frame(width: 76, height: 76)
                .background(Theme.ember.opacity(0.12), in: .rect(cornerRadius: 22, style: .continuous))
            Text("Transcribe from any app")
                .font(Theme.display(.title))
                .multilineTextAlignment(.center)
            Text("""
                Add **Transcribe** to Control Center. When something worth keeping starts playing, swipe down \
                and tap it; you never leave the app you’re in.
                """)
                .font(.callout)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func footer(_ state: ControlCenterStatus.State) -> some View {
        VStack(spacing: 10) {
            switch state {
            case .added:
                Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(ProminentButtonStyle(tint: Theme.sage))
            case .notAdded, .unknown:
                Label {
                    Text("Waiting for Transcribe…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityLabel("Waiting for you to add Transcribe")
                Button { dismiss() } label: { Text("Later").frame(maxWidth: .infinity) }
                    .buttonStyle(QuietButtonStyle())
            case .unavailable:
                // The check failed: the user tells us instead.
                Button { dismiss() } label: { Text("I’ve added it").frame(maxWidth: .infinity) }
                    .buttonStyle(ProminentButtonStyle())
            }
        }
        .font(.headline)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Theme.paper.opacity(0.95))
    }
}

private struct AddedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76))
                .foregroundStyle(Theme.sage)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.top, 40)
            Text("You’re set")
                .font(Theme.display(.largeTitle))
            Text("""
                **Transcribe** is in place. Next time something worth keeping plays, swipe down and tap it. Tap \
                again, or the red indicator, to stop.
                """)
                .font(.callout)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
