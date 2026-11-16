import AnamnesisKit
import SwiftUI

/// The image a transcript is shared as (spec 016 R6): title, speaker, the text, and the Anamnesis mark and name at
/// the foot. Drawn at 360 pt wide and rendered at 3× (1080 px, the width Instagram and most messengers keep); at least
/// 4:5 tall, longer for longer poems. Colours are fixed per style so the card looks the same in light and dark mode.
struct PoemShareCard: View {
    enum Style: String, CaseIterable, Identifiable {
        case paper, night, ember

        var id: Self { self }

        var name: String {
            switch self {
            case .paper: "Paper"
            case .night: "Night"
            case .ember: "Ember"
            }
        }
    }

    let poem: PoemExport
    let style: Style

    static let width: CGFloat = 360
    /// Beyond this the text ends in "…"; a card is a taste of the transcript, not a scroll.
    static let maxLines = 30

    var body: some View {
        let palette = Palette(style)
        VStack(alignment: .leading, spacing: 0) {
            Text("“")
                .font(.system(size: 64, weight: .bold, design: .serif))
                .foregroundStyle(palette.accent)
                .frame(height: 40, alignment: .top)
                .accessibilityHidden(true)
            Text(poem.heading)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(palette.ink)
                .padding(.top, 14)
            if let poet = poem.poet {
                Text(poet)
                    .font(.system(size: 17, design: .serif))
                    .italic()
                    .foregroundStyle(palette.accent)
                    .padding(.top, 4)
            }
            Rectangle()
                .fill(palette.accent.opacity(0.6))
                .frame(width: 36, height: 1.5)
                .padding(.vertical, 20)
            Text(poem.body.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 17, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(palette.ink)
                .lineLimit(Self.maxLines)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 32)
            brand(palette)
        }
        .padding(32)
        .frame(width: Self.width, alignment: .leading)
        .frame(minHeight: Self.width * 5 / 4)
        .background(palette.background)
        .environment(\.colorScheme, style == .paper ? .light : .dark)
    }

    private func brand(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            AppMark(size: 28)
                .overlay {
                    // On the ember card the ember tile needs an edge to stand out.
                    RoundedRectangle(cornerRadius: 28 * 0.225, style: .continuous)
                        .strokeBorder(.white.opacity(style == .ember ? 0.5 : 0), lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 0) {
                Text("Anamnesis")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("Transcribe anything you hear")
                    .font(.system(size: 11, design: .serif))
                    .italic()
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.secondary.opacity(0.25)).frame(height: 0.5)
        }
    }
}

/// Fixed colours per style (the card is an image; it must not follow the viewer's appearance).
private struct Palette {
    let background: AnyShapeStyle
    let ink: Color
    let secondary: Color
    let accent: Color

    init(_ style: PoemShareCard.Style) {
        switch style {
        case .paper:
            background = AnyShapeStyle(Color.fixed(0xF6F1E7))
            ink = .fixed(0x1F1B16)
            secondary = .fixed(0x6E655A)
            accent = .fixed(0xB8452A)
        case .night:
            background = AnyShapeStyle(LinearGradient(colors: [.fixed(0x1D1B18), .fixed(0x0E0D0B)],
                                                      startPoint: .top, endPoint: .bottom))
            ink = .fixed(0xF2ECE1)
            secondary = .fixed(0xA69D90)
            accent = .fixed(0xF0785A)
        case .ember:
            background = AnyShapeStyle(LinearGradient(colors: [.fixed(0xC24F30), .fixed(0x7E2A14)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            ink = .fixed(0xFFF8F0)
            secondary = .fixed(0xF6D9CC)
            accent = .fixed(0xFFE2B8)
        }
    }
}

private extension Color {
    static func fixed(_ rgb: UInt32) -> Color { Color(light: rgb, dark: rgb) }
}
