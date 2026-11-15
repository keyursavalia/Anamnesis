import SwiftUI

/// The brand mark drawn in code (spec 015 R7): an italic New York "A" on an ember tile. The App Store icon is
/// release prep and out of scope; this stands in on the welcome and Settings screens.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text("A")
                    .font(.system(size: size * 0.62, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                    .offset(y: -size * 0.02)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(size * 0.12)
            }
            .frame(width: size, height: size)
            .shadow(color: Theme.ember.opacity(0.3), radius: size * 0.2, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
