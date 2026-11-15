import SwiftUI

/// The welcome (spec 015 R1, redesigned in spec 016 R8–R9): three pages on a dark, slowly moving glow ("night
/// recital"): what Anamnesis does, how to capture (the Control Center control first, it is the quickest), and the
/// privacy promise. Shown once on first launch and again from Settings → How it works. Always dark, whatever the
/// system appearance, so it feels like a stage rather than a form. Reduce Motion stills every animation.
struct OnboardingView: View {
    let finish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pageCount = 3

    var body: some View {
        ZStack {
            AuroraBackground(page: page, animates: !reduceMotion)
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    WelcomePage(isActive: page == 0, animates: !reduceMotion).tag(0)
                    CapturePage(isActive: page == 1, animates: !reduceMotion).tag(1)
                    PrivacyPage(isActive: page == 2).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                controls
            }
        }
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .topTrailing) {
            if page < Self.pageCount - 1 {
                Button("Skip", action: finish)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Night.secondary)
                    .padding(20)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 20) {
            PageDots(count: Self.pageCount, current: page)
            Button {
                if page < Self.pageCount - 1 {
                    withAnimation(.smooth) { page += 1 }
                } else {
                    finish()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(page < Self.pageCount - 1 ? "Continue" : "Get started")
                    Image(systemName: page < Self.pageCount - 1 ? "arrow.right" : "sparkles")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.headline)
                .foregroundStyle(Night.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Night.cream, in: .capsule)
                .shadow(color: Night.glow.opacity(0.45), radius: 24, y: 8)
            }
            .buttonStyle(CardButtonStyle())
            .sensoryFeedback(.selection, trigger: page)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
    }
}

/// The welcome's own palette: always night, whatever the system appearance.
enum Night {
    static let base = Color(light: 0x0E0D0B, dark: 0x0E0D0B)
    static let cream = Color(light: 0xF6EFE3, dark: 0xF6EFE3)
    static let secondary = Color(light: 0xC9BEAF, dark: 0xC9BEAF)
    static let ink = Color(light: 0x1F1B16, dark: 0x1F1B16)
    static let glow = Color(light: 0xF0785A, dark: 0xF0785A)
    static let amber = Color(light: 0xE8B04B, dark: 0xE8B04B)
    static let sage = Color(light: 0x8CC09A, dark: 0x8CC09A)
}

// MARK: - Pages

private struct WelcomePage: View {
    let isActive: Bool
    let animates: Bool

    var body: some View {
        PageLayout {
            ZStack {
                FloatingVerses(animates: animates && isActive)
                GlowingMark(animates: animates)
            }
            .frame(height: 230)
        } content: {
            Text("Keep the poems\nyou hear.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Night.cream)
                .multilineTextAlignment(.center)
                .reveal(isActive, delay: 0.1)
            Text("""
                Anamnesis can listen to the reels you’re watching and turn the poem into words you can keep, \
                share and visit again.
                """)
                .font(.body)
                .foregroundStyle(Night.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .reveal(isActive, delay: 0.25)
            Text("“Anamnesis” is the Greek for remembering.")
                .font(.system(.footnote, design: .serif))
                .italic()
                .foregroundStyle(Night.amber.opacity(0.9))
                .reveal(isActive, delay: 0.4)
        }
    }
}

private struct CapturePage: View {
    let isActive: Bool
    let animates: Bool

    var body: some View {
        PageLayout {
            ControlCenterMock(animates: animates && isActive)
                .frame(height: 186)
        } content: {
            Text("Capture in one swipe.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Night.cream)
                .multilineTextAlignment(.center)
                .reveal(isActive, delay: 0.1)
            Text("""
                Add **Capture poem** to Control Center. When a poem starts, swipe down and tap it. You never \
                leave TikTok or Instagram, and you never miss the first line.
                """)
                .font(.body)
                .foregroundStyle(Night.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .reveal(isActive, delay: 0.25)
            VStack(spacing: 8) {
                Option(symbol: "switch.2", title: "Capture poem control", detail: "Fastest · from any app",
                       highlighted: true)
                Option(symbol: "waveform", title: "Or the Listen button", detail: "Open Anamnesis, tap the orb",
                       highlighted: false)
                Option(symbol: "books.vertical.fill", title: "Then it’s in your Library",
                       detail: "Stop, and each poem lands there", highlighted: false)
            }
            .reveal(isActive, delay: 0.4)
        }
    }
}

private struct PrivacyPage: View {
    let isActive: Bool

    var body: some View {
        PageLayout {
            ZStack {
                Circle().fill(Night.sage.opacity(0.18)).frame(width: 170, height: 170).blur(radius: 30)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(Night.sage, Night.cream)
                    .symbolEffect(.bounce, value: isActive)
            }
            .frame(height: 230)
        } content: {
            Text("Private by design.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Night.cream)
                .multilineTextAlignment(.center)
                .reveal(isActive, delay: 0.1)
            VStack(spacing: 10) {
                Option(symbol: "speaker.wave.2.fill", title: "Only what other apps play",
                       detail: "Never your microphone", highlighted: false)
                Option(symbol: "iphone", title: "Transcribed on this iPhone", detail: "No account, no cloud",
                       highlighted: false)
                Option(symbol: "trash.fill", title: "Audio is deleted", detail: "Once it has become text",
                       highlighted: false)
            }
            .reveal(isActive, delay: 0.25)
        }
    }
}

// MARK: - Pieces

/// Art on top, then the page's text, centred, scrolling only if the text is very large.
private struct PageLayout<Art: View, Content: View>: View {
    @ViewBuilder let art: Art
    @ViewBuilder let content: Content

    init(@ViewBuilder art: () -> Art, @ViewBuilder content: () -> Content) {
        self.art = art()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 24)
                art
                content
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

/// A glassy row: icon, title, detail. The highlighted one glows ember.
private struct Option: View {
    let symbol: String
    let title: String
    let detail: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(highlighted ? Night.ink : Night.cream)
                .frame(width: 40, height: 40)
                .background(highlighted ? AnyShapeStyle(Night.glow) : AnyShapeStyle(.white.opacity(0.1)),
                            in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Night.cream)
                Text(detail).font(.footnote).foregroundStyle(Night.secondary)
            }
            Spacer(minLength: 0)
            if highlighted {
                Text("Best")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Night.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Night.amber, in: .capsule)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(highlighted ? Night.glow.opacity(0.7) : .white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Fades and lifts in once the page is showing; resets when it leaves, so returning plays it again.
    func reveal(_ isActive: Bool, delay: Double) -> some View {
        opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 14)
            .blur(radius: isActive ? 0 : 6)
            .animation(.smooth(duration: 0.7).delay(isActive ? delay : 0), value: isActive)
    }
}

#Preview {
    OnboardingView {}
}
