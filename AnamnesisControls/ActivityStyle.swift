import SwiftUI

/// The Live Activity's colours (spec 017 R1). The extension cannot see the app's `Theme`, and SwiftUI does not
/// belong in AnamnesisKit, so these mirror the app's night palette by value: keep them in step with
/// `Anamnesis/Design/Theme.swift` (dark values) and `Night` in the welcome. Fixed, not adaptive: the activity always
/// sits on its own dark ink background, like the Dynamic Island around it.
enum ActivityPalette {
    static let ink = Color(rgb: 0x14120F)
    static let cream = Color(rgb: 0xF6EFE3)
    static let secondary = Color(rgb: 0xC9BEAF)
    /// Ember for text and symbols on dark (the app's dark-mode accent).
    static let ember = Color(rgb: 0xF0785A)
    /// Ember behind text: buttons and pills.
    static let emberFill = Color(rgb: 0xC24F30)
    static let sage = Color(rgb: 0x8CC09A)
}

/// The app mark: the app icon's artwork (`AppLogo` in this extension's catalog, a small copy of the app's) on an
/// icon-shaped tile, the same as the app's `AppMark`. `circular` for the compact and minimal island, where a square's
/// corner reaches past the island's curve; a circle sits concentric with it (HIG).
struct ActivityMark: View {
    var size: CGFloat = 40
    var circular = false

    var body: some View {
        Image("AppLogo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(circular ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: size * 0.225, style: .continuous)))
            .accessibilityHidden(true)
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
