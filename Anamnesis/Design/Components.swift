import SwiftUI

// Small building blocks every screen shares (spec 015). Kept deliberately few.

/// A raised paper card.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }

    /// The paper background behind a whole screen, under lists and scroll views alike.
    func paperBackground() -> some View {
        background(Theme.paper.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }

    /// A row of a plain `List` that should look like a card on paper, keeping swipe actions. Capped at the reading
    /// width and centred, so cards do not stretch across an iPad or a landscape phone.
    func cardRow() -> some View {
        frame(maxWidth: Theme.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: Theme.gutter, bottom: 6, trailing: Theme.gutter))
    }
}

/// "MOMENT 2 · 0:41" — tracking-wide uppercase over a group.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.inkSecondary

    init(_ text: String, color: Color = Theme.inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.eyebrow)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// A status capsule: "3 to review", "Transcribing", "In library".
struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.ember
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(filled ? Color.white : tint)
        .background(filled ? AnyShapeStyle(tint == Theme.ember ? Theme.emberFill : tint)
                           : AnyShapeStyle(tint.opacity(0.13)), in: .capsule)
    }
}

/// A tag or filter chip.
struct Chip: View {
    let text: String
    var isSelected = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Theme.ink)
            .background(isSelected ? AnyShapeStyle(Theme.emberFill) : AnyShapeStyle(Theme.sunken), in: .capsule)
            .contentShape(.capsule)
    }
}

/// The filled ember capsule for the one main action on a card.
struct ProminentButtonStyle: ButtonStyle {
    var tint: Color = Theme.emberFill

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(tint, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A whole card as one button: a slight press-in, no row highlight. Used instead of a hidden `NavigationLink`, which
/// VoiceOver cannot reach.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// The quiet capsule next to it.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .foregroundStyle(Theme.ink)
            .background(Theme.sunken, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A small ornament between a poem's heading and its text.
struct Fleuron: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().frame(width: 28, height: 0.5)
            Image(systemName: "sparkle").font(.caption2)
            Rectangle().frame(width: 28, height: 0.5)
        }
        .foregroundStyle(Theme.ember.opacity(0.7))
        .accessibilityHidden(true)
    }
}

/// An inline error line, the same everywhere.
struct ErrorLine: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Theme.danger)
    }
}
