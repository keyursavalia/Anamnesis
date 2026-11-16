import SwiftUI

// Privacy policy and Terms of Use (spec 016 R11). The wording is a first draft that describes what the code does;
// the owner reviews it before release (RISKS R-09). Keep it in step with CLAUDE.md invariants 1–2.

struct PrivacyView: View {
    var body: some View {
        LegalPage(title: "Privacy", summary: LegalSummary(
            symbol: "hand.raised.fill", tint: Theme.sage, title: "Your data stays with you",
            text: "Anamnesis has no account, no servers and no analytics. Nothing you record or keep is sent "
                + "to us or anyone else."), sections: Self.sections)
    }

    private static let sections: [LegalSection] = [
        LegalSection("What the app records", """
            Only while you transcribe, and only the sound other apps play on your device (for example a video, \
            a podcast or a talk), through Apple's screen-sharing system. The app never uses your microphone and \
            never keeps the video.
            """),
        LegalSection("How transcription works", """
            Apple's speech recognition turns the recorded sound into text on your device. The first time, iOS \
            downloads Apple's English speech model through the system; Anamnesis itself makes no network requests.
            """),
        LegalSection("What is kept, and where", """
            Recorded audio is stored on your device only until it is transcribed, then deleted. Your transcripts \
            (their text, title, speaker and source) are stored on your device and included in your device backup; \
            recorded audio is not. Whether a tip or a What's New note was shown is also kept on your device only.
            """),
        LegalSection("When you share", """
            Nothing leaves the app unless you choose to. Copy puts the transcript on your clipboard; Share card \
            makes an image on your device and hands it to the share sheet, where you choose the destination.
            """),
        LegalSection("Links you save", """
            If a transcript's source is a link, tapping it asks iOS to open it in the app or website it belongs \
            to. What happens there is governed by that service's own privacy policy.
            """),
        LegalSection("No tracking", """
            No analytics, advertising, tracking or third-party SDKs. The app does not collect data, so it has none \
            to sell or share. Its App Store privacy label is "Data Not Collected".
            """),
        LegalSection("Deleting your data", """
            Delete a transcript from the Library or a recording from Transcribe at any time. Settings → App \
            settings → Delete all data removes every transcript, recording and the app's log. Deleting the app \
            removes everything too.
            """),
        LegalSection("Changes", """
            If this policy changes, the new version will be in the app with its effective date.
            """)
    ]
}

struct TermsView: View {
    var body: some View {
        LegalPage(title: "Terms of Use", summary: LegalSummary(
            symbol: "doc.text.fill", tint: Theme.ember, title: "The short version",
            text: "Anamnesis is a personal notebook for the words you hear. Keep them for yourself, credit the "
                + "people who said them when you share, and respect their rights."), sections: Self.sections)
    }

    private static let sections: [LegalSection] = [
        LegalSection("Agreement", """
            By using Anamnesis you agree to these terms. They add to Apple's Licensed Application End User \
            License Agreement, which also applies.
            """),
        LegalSection("Personal use", """
            Anamnesis is for your personal, non-commercial use: to keep a private record of what you hear and \
            to share it with credit.
            """),
        LegalSection("Words belong to their authors", """
            What you transcribe remains the work of its authors and rights holders: poets, speakers, writers. \
            Saving it for yourself does not give you any right to republish it. When you share a card, include \
            the speaker's name, and do not use shared transcripts commercially or claim them as your own.
            """),
        LegalSection("Your responsibility", """
            Only transcribe content you are allowed to listen to, and follow the terms of the apps it plays in. \
            Do not use Anamnesis to infringe anyone's rights.
            """),
        LegalSection("Transcripts may be imperfect", """
            Transcription is automatic and can mishear words. Check a transcript against its source before you \
            rely on it or share it.
            """),
        LegalSection("Links and other apps", """
            Source links open other apps and websites that we do not control and are not responsible for.
            """),
        LegalSection("No warranty", """
            The app is provided as is, without warranties of any kind, to the extent permitted by law. To the \
            extent permitted by law, we are not liable for any loss arising from its use, including lost data; \
            keep a backup of anything important.
            """),
        LegalSection("Changes", """
            These terms may be updated; the current version is always in the app with its effective date.
            """)
    ]
}

// MARK: - Page

struct LegalSection: Identifiable {
    let heading: String
    let text: String
    var id: String { heading }

    init(_ heading: String, _ text: String) {
        self.heading = heading
        self.text = text
    }
}

struct LegalSummary {
    let symbol: String
    let tint: Color
    let title: String
    let text: String
}

/// A readable legal page: a summary card, then numbered sections, then the effective date.
private struct LegalPage: View {
    let title: String
    let summary: LegalSummary
    let sections: [LegalSection]

    static let effectiveDate = "15 November 2026"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: summary.symbol)
                        .font(.title2)
                        .foregroundStyle(summary.tint)
                        .frame(width: 48, height: 48)
                        .background(summary.tint.opacity(0.13), in: .rect(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title).font(.headline).foregroundStyle(Theme.ink)
                        Text(summary.text).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }
                }
                .card()
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(.subheadline, design: .serif, weight: .bold))
                                .foregroundStyle(Theme.ember)
                            Text(section.heading).font(Theme.display(.title3)).foregroundStyle(Theme.ink)
                        }
                        Text(section.text)
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Effective \(Self.effectiveDate)")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: Theme.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
