import SwiftUI

/// Spec 020 R11 (D-039): after the App Store installs an update, the next launch shows what changed, once. Fully
/// offline: the app compares its own version with the last one it showed notes for. There is no way to learn that
/// a newer version *exists* without asking a server, so the app never does; App Store automatic updates deliver it.
enum WhatsNew {
    struct Item: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    /// Notes per marketing version. Add an entry with each release that has something worth telling.
    static let notes: [String: [Item]] = [
        "1.0": [
            Item(symbol: "waveform", title: "Transcribe anything",
                 detail: "Poems, speeches, stories, plans: whatever plays on your device becomes text you keep."),
            Item(symbol: "square.and.pencil", title: "Write your own",
                 detail: "Add a transcript by hand from the Library, with the same editor."),
            Item(symbol: "lightbulb", title: "Quiet tips",
                 detail: "Now and then, a hint about Control Center and the Action Button.")
        ]
    ]

    static let lastShownKey = "whatsNew.lastShownVersion"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// The notes to show now, if any. A fresh install shows none (the welcome covers it) and remembers its version.
    static func pending(defaults: UserDefaults = .standard, isFreshInstall: Bool) -> [Item]? {
        let current = currentVersion
        let lastShown = defaults.string(forKey: lastShownKey)
        guard lastShown != current else { return nil }
        defaults.set(current, forKey: lastShownKey)
        guard !isFreshInstall, let items = notes[current], !items.isEmpty else { return nil }
        return items
    }
}

struct WhatsNewSheet: View {
    let items: [WhatsNew.Item]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                AppMark(size: 72)
                Text("What’s new").font(Theme.display(.largeTitle)).foregroundStyle(Theme.ink)
                Text("Version \(WhatsNew.currentVersion)").font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            .padding(.top, 36)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.headline)
                            .foregroundStyle(Theme.ember)
                            .frame(width: 40, height: 40)
                            .background(Theme.ember.opacity(0.12), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline).foregroundStyle(Theme.ink)
                            Text(item.detail).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: 440, alignment: .leading)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(ProminentButtonStyle())
            .frame(maxWidth: 440)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.large])
    }
}
