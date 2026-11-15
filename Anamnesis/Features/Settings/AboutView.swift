import SwiftUI

/// About Anamnesis (spec 016 R11): what the name means, how the app works as a four-step timeline that draws itself
/// in, what it stands for, and the version.
struct AboutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                hero
                name
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow("How it works", color: Theme.ember)
                    Timeline(revealed: revealed)
                }
                beliefs
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: Theme.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.9).delay(0.15)) { revealed = true }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            AppMark(size: 96)
                .scaleEffect(revealed ? 1 : 0.85)
                .opacity(revealed ? 1 : 0)
            Text("Anamnesis").font(Theme.display(.largeTitle)).foregroundStyle(Theme.ink)
            Text("an · am · NEE · sis").font(.footnote.monospaced()).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("The name", color: Theme.ember)
            Text("ἀνάμνησις — *recollection*")
                .font(Theme.verse(.title3))
                .foregroundStyle(Theme.ink)
            Text("""
                To the Greeks, anamnesis was the act of remembering: Plato thought that to learn something is to \
                recall what we already knew. A poem you heard once in a reel, then lost to the scroll, is like that: \
                you knew it, for a moment. Anamnesis helps you call it back, and keep it.
                """)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(4)
        }
    }

    private var beliefs: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("What it stands for", color: Theme.ember)
            belief("lock.fill", "Private by construction",
                   "No account, no cloud, no analytics. What you hear stays on your phone.")
            belief("text.quote", "The words are the point",
                   "Audio is only a means; it is deleted once the poem is text you can read and edit.")
            belief("person.fill", "Poets first",
                   "Every card you share carries the poet’s name. Credit the people whose words move you.")
        }
    }

    private func belief(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Theme.ember)
                .frame(width: 36, height: 36)
                .background(Theme.ember.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(text).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return VStack(spacing: 6) {
            Fleuron()
            Text("Version \(version) (\(build))").font(.footnote).foregroundStyle(Theme.inkSecondary)
            Text("Made for people who keep poems.").font(Theme.verse(.footnote)).italic()
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Hear → Capture → Transcribe → Keep, joined by a line that grows as the steps appear one after another.
private struct Timeline: View {
    let revealed: Bool

    private struct Step {
        let symbol: String
        let title: String
        let text: String
    }

    private static let steps = [
        Step(symbol: "music.note", title: "Hear",
             text: "A poem plays in a reel on TikTok, Instagram or anywhere else on your phone."),
        Step(symbol: "switch.2", title: "Capture",
             text: "Swipe down and tap Capture poem in Control Center, or tap the orb on Listen. Only the sound "
                + "other apps play is captured, never your microphone."),
        Step(symbol: "waveform.and.magnifyingglass", title: "Transcribe",
             text: "When you stop, Apple’s speech recognition turns the recital into text, right on your phone."),
        Step(symbol: "books.vertical.fill", title: "Keep",
             text: "Each poem lands in your Library. Fix a word, add the poet, paste the reel’s link, share it "
                + "as a card.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.steps.indices, id: \.self) { index in
                let step = Self.steps[index]
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        Image(systemName: step.symbol)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.emberFill, in: .circle)
                        if index < Self.steps.count - 1 {
                            Rectangle()
                                .fill(Theme.ember.opacity(0.35))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                                .scaleEffect(y: revealed ? 1 : 0, anchor: .top)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title).font(Theme.display(.title3)).foregroundStyle(Theme.ink)
                        Text(step.text).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                // Rows are as tall as their text, so the connector line fills exactly that height.
                .fixedSize(horizontal: false, vertical: true)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 12)
                .animation(.smooth(duration: 0.6).delay(Double(index) * 0.15), value: revealed)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
