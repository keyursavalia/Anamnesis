import SwiftUI

/// About Anamnesis (spec 016 R11; rewritten in spec 020 R12): the mark, what the name means, why the app was built
/// (in the developer's voice), the version, and the developer's name, quietly, linking to LinkedIn. Sized to fit one
/// iPhone screen; it scrolls only at very large text sizes.
struct AboutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// Owner's draft (spec 020): edit freely; it is the only copy.
    private static let why = """
        I love poetry. Late at night I’d hear a few lines in a reel that stopped me mid-scroll, and by morning \
        they were gone, buried under a hundred other videos. I wanted a quiet place to keep those words, one that \
        never asks for an account and never sends anything anywhere. So I built Anamnesis, first for myself, and \
        now for anyone who has wished they could hold on to something they heard.
        """

    private static let developer = "KEYUR DIPAKBHAI SAVALIA"
    // A literal that is a valid URL; the force-unwrap cannot fail.
    private static let developerURL = URL(string: "https://www.linkedin.com/in/keyursavalia")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                name
                why
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: Theme.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paperBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.9).delay(0.15)) { revealed = true }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            AppMark(size: 80)
                .scaleEffect(revealed ? 1 : 0.85)
                .opacity(revealed ? 1 : 0)
            Text("Anamnesis").font(Theme.display(.largeTitle)).foregroundStyle(Theme.ink)
            Text("an · am · NEE · sis").font(.footnote.monospaced()).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("The name", color: Theme.ember)
            Text("ἀνάμνησις — *recollection*")
                .font(Theme.verse(.title3))
                .foregroundStyle(Theme.ink)
            Text("""
                To the Greeks, anamnesis was the act of remembering. Something you heard once, then lost to the \
                scroll, is like that: you knew it, for a moment. Anamnesis helps you call it back, and keep it.
                """)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(3)
        }
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Why it was built", color: Theme.ember)
            Text(Self.why)
                .font(Theme.verse(.body))
                .italic()
                .foregroundStyle(Theme.ink)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    // A margin rule, like a quotation set in a book.
                    Capsule().fill(Theme.ember.opacity(0.6)).frame(width: 2)
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 10)
        }
    }

    private var footer: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return VStack(spacing: 10) {
            Fleuron()
            Text("Version \(version)").font(.footnote).foregroundStyle(Theme.inkSecondary)
            // Present, not prominent: small, light, spaced capitals.
            Link(destination: Self.developerURL) {
                Text(Self.developer)
                    .font(.caption2.weight(.medium))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.7))
            }
            .accessibilityLabel("Made by Keyur Dipakbhai Savalia")
            .accessibilityHint("Opens LinkedIn")
        }
        .frame(maxWidth: .infinity)
    }
}
