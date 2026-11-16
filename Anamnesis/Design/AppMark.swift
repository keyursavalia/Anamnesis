import SwiftUI

/// The brand mark: the app icon's artwork (`AppLogo`, baked from `AnamnesisIcon.icon` at the icon's own crop) on an
/// icon-shaped tile. Used wherever the app shows its face: welcome, Settings, About, the share card.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: max(0.5, size / 96))
            }
            .shadow(color: Theme.ember.opacity(0.3), radius: size * 0.2, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
