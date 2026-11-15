import SwiftUI
import UIKit

/// The app's look (spec 015): paper and ink, one ember accent, New York for poems and titles, SF for controls.
/// Every colour adapts to dark mode; nothing outside this file names a hex value.
enum Theme {
    // MARK: - Colour

    /// The page: warm paper by day, lamp-lit ink by night.
    static let paper = Color(light: 0xF6F1E7, dark: 0x12110F)
    /// Cards and raised surfaces.
    static let surface = Color(light: 0xFFFDF8, dark: 0x1D1B18)
    /// Wells inside a card: chips, fields, the excerpt bar.
    static let sunken = Color(light: 0xEDE6D8, dark: 0x2A2723)
    static let ink = Color(light: 0x1F1B16, dark: 0xF2ECE1)
    static let inkSecondary = Color(light: 0x6E655A, dark: 0xA69D90)
    static let hairline = Color(light: 0xE2D9C8, dark: 0x332F2A)
    /// The one accent: capture, primary actions, the tab tint.
    static let ember = Color(light: 0xB8452A, dark: 0xF0785A)
    static let emberDeep = Color(light: 0x8E3018, dark: 0xA8432A)
    /// Ember behind white text: deep enough in dark mode for 4.5:1 contrast.
    static let emberFill = Color(light: 0xB8452A, dark: 0xC24F30)
    /// Words the transcriber was unsure of (PRD principle 4: show them, never hide them).
    static let unsure = Color(light: 0xA86A00, dark: 0xE8B04B)
    /// Saved, done, in the library.
    static let sage = Color(light: 0x4F7A5A, dark: 0x8CC09A)
    static let danger = Color(light: 0xB3261E, dark: 0xFF8A80)

    // MARK: - Type

    /// Screen and poem titles.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif, weight: .semibold)
    }

    /// Poem text. Scales with Dynamic Type.
    static func verse(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }

    /// Small uppercase label above a group ("MOMENT 2 · 0:41").
    static let eyebrow = Font.caption.weight(.semibold)

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 22
    static let gutter: CGFloat = 20
    /// A comfortable reading measure on iPad and landscape.
    static let readingWidth: CGFloat = 620

    // MARK: - UIKit appearance

    /// Navigation titles in New York. SwiftUI has no modifier for the bar's title font, so this is the one place
    /// the app sets UIKit appearance.
    static func applyAppearance() {
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: serif(.largeTitle, weight: .bold)]
        appearance.titleTextAttributes = [.font: serif(.headline, weight: .semibold)]
    }

    private static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let weighted = base.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        let descriptor = weighted.withDesign(.serif) ?? weighted
        return UIFont(descriptor: descriptor, size: 0)
    }
}

extension Color {
    /// A colour that follows the interface style, from two 0xRRGGBB values.
    ///
    /// `nonisolated` and `@Sendable` on purpose: SwiftUI resolves colours on its async render thread, and the app
    /// target's default `MainActor` isolation would otherwise make the provider main-actor-only, which traps at run
    /// time (`EXC_BREAKPOINT` on `com.apple.SwiftUI.AsyncRenderer`, spec 015). `UIColor` is `Sendable`.
    nonisolated init(light: UInt32, dark: UInt32) {
        let lightColor = UIColor(rgb: light)
        let darkColor = UIColor(rgb: dark)
        self.init(uiColor: UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}

private extension UIColor {
    nonisolated convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
