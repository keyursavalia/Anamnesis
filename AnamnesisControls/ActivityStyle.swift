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
    /// Ember behind text: buttons and the mark.
    static let emberFill = Color(rgb: 0xC24F30)
    static let emberDeep = Color(rgb: 0xA8432A)
    static let sage = Color(rgb: 0x8CC09A)
}

/// The app mark (an italic New York "A" on an ember tile), the same drawing as the app's `AppMark`.
struct ActivityMark: View {
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [ActivityPalette.emberFill, ActivityPalette.emberDeep],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(verbatim: "A")
                    .font(.system(size: size * 0.62, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
