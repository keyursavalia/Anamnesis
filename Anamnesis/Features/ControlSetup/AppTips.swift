import SwiftUI
import TipKit
import UIKit

// Spec 020 R10 (D-038): small, periodic hints about the quickest ways to start, through TipKit. TipKit keeps its
// state in a local datastore (no CloudKit container is configured), so nothing leaves the device. At most one tip a
// week, each a few times at most; closing one retires it for good.

enum AppTips {
    /// Once, at launch. A second call throws (already configured), which is harmless and ignored.
    static func configure() {
        try? Tips.configure([.displayFrequency(.weekly), .datastoreLocation(.applicationDefault)])
        ActionButtonTip.isPhone = UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Mirrors `ControlCenterStatus` into the tips' rules.
    static func controlStatusChanged(_ state: ControlCenterStatus.State) {
        ControlCenterTip.isStatusKnown = state != .unknown
        ControlCenterTip.isControlAdded = state == .added
    }

    /// Counts foreground launches, for the Action Button tip's rule.
    static func appBecameActive() {
        Task { await ActionButtonTip.appOpened.donate() }
    }
}

/// "Add Transcribe to Control Center", while it is not placed.
struct ControlCenterTip: Tip {
    static let showGuide = "show-guide"

    @Parameter static var isStatusKnown: Bool = false
    @Parameter static var isControlAdded: Bool = false

    var title: Text { Text("Transcribe from any app") }
    var message: Text? {
        Text("Add **Transcribe** to Control Center and start without leaving what you’re watching.")
    }
    var image: Image? { Image(systemName: "switch.2") }

    var actions: [Action] {
        Action(id: Self.showGuide, title: "Show me how")
    }

    var rules: [Rule] {
        #Rule(Self.$isStatusKnown) { $0 }
        #Rule(Self.$isControlAdded) { !$0 }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(5)
    }
}

/// "Set the Action Button to Transcribe", on iPhone only (there is no API to ask whether a device has one, so the
/// wording is conditional, D-038), after a few launches so it never greets a brand-new user.
struct ActionButtonTip: Tip {
    static let appOpened = Tips.Event(id: "app-opened")
    /// Set at configure time (`UIDevice` is main-actor only; a parameter's default is not).
    @Parameter static var isPhone: Bool = false

    var title: Text { Text("Got an Action Button?") }
    var message: Text? {
        Text("Set it to Transcribe: Settings → Action Button → Controls → **Transcribe**. One press starts it.")
    }
    var image: Image? { Image(systemName: "button.programmable") }

    var rules: [Rule] {
        #Rule(Self.$isPhone) { $0 }
        #Rule(Self.appOpened) { $0.donations.count >= 3 }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(3)
    }
}

/// The app's card look for an inline tip: icon badge, title, message, actions as capsules, a close button.
struct CardTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                configuration.image?
                    .font(.title2)
                    .foregroundStyle(Theme.ember)
                    .frame(width: 44, height: 44)
                    .background(Theme.ember.opacity(0.12), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    configuration.title?.font(.headline).foregroundStyle(Theme.ink)
                    configuration.message?.font(.footnote).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    configuration.tip.invalidate(reason: .tipClosed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.sunken, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tip")
            }
            if !configuration.actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(configuration.actions) { action in
                        Button(action: action.handler) {
                            action.label().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ProminentButtonStyle())
                    }
                }
            }
        }
        .card(padding: 16)
        .padding(.vertical, 6)
    }
}
