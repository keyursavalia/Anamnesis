#if DEBUG
import Foundation
import SwiftData
import TipKit

// SPIKE: App Store screenshots (docs/APP_STORE_SUBMISSION.md B4). Launched with `-screenshotScene <name>`, the app
// seeds `ScreenshotSeed`, skips the welcome, sheets and tips, and opens one screen so a script can capture it.
// The argument lives in the launch's argument domain only; nothing is written for the next normal launch except the
// welcome/What's New flags, as a user who finished the welcome would have.
enum ScreenshotScene: String {
    case library, detail, editor, share, privacy

    /// The transcript the detail, editor and share scenes open.
    static let heroTitle = "Hope is the thing with feathers"

    static let current: ScreenshotScene? = UserDefaults.standard.string(forKey: "screenshotScene")
        .flatMap(Self.init(rawValue:))

    var tab: RootView.TabID { self == .privacy ? .settings : .library }
    var opensHero: Bool { self == .detail || self == .editor || self == .share }

    /// Before the first view: a finished welcome, no What's New, no guide sheet, no tips.
    static func prepareLaunch() {
        guard current != nil else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "onboarding.completed")
        defaults.set(true, forKey: "controlNudge.sheetShown")
        defaults.set(WhatsNew.currentVersion, forKey: WhatsNew.lastShownKey)
        Tips.hideAllTipsForTesting()
    }

    static func seed(_ container: ModelContainer) {
        guard current != nil else { return }
        try? ScreenshotSeed.replace(in: container.mainContext)
    }
}
#endif
