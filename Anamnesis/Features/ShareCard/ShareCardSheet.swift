import AnamnesisKit
import SwiftUI

/// *Share card* (spec 016 R6): pick a style, see the exact image, share it anywhere the share sheet reaches (Messages,
/// Instagram, Photos, …). The image is rendered on device; nothing is uploaded by the app.
struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let poem: PoemExport
    @State private var style = PoemShareCard.Style.paper
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    preview
                    stylePicker
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { shareButton }
            .paperBackground()
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task(id: style) { render() }
        }
    }

    /// The rendered image itself, so what you see is exactly what is shared.
    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 18))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                .accessibilityLabel("Card preview: \(poem.heading)")
                .transition(.opacity)
                .id(style)
        } else {
            ProgressView().frame(height: 420)
        }
    }

    private var stylePicker: some View {
        HStack(spacing: 18) {
            ForEach(PoemShareCard.Style.allCases) { option in
                Button {
                    withAnimation(.smooth) { style = option }
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(option.swatch)
                            .frame(width: 44, height: 44)
                            .overlay { Circle().strokeBorder(Theme.hairline, lineWidth: 1) }
                            .padding(3)
                            .overlay {
                                Circle().strokeBorder(style == option ? Theme.ember : .clear, lineWidth: 2)
                            }
                        Text(option.name)
                            .font(.caption.weight(style == option ? .semibold : .regular))
                            .foregroundStyle(style == option ? Theme.ink : Theme.inkSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.name) style")
                .accessibilityAddTraits(style == option ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: style)
    }

    private var shareButton: some View {
        Group {
            if let image {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview(poem.heading, image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
            } else {
                Label("Preparing…", systemImage: "hourglass").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(ProminentButtonStyle())
        .font(.headline)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Theme.paper.opacity(0.95))
    }

    /// Main actor, as ImageRenderer requires; a card renders in a few milliseconds.
    private func render() {
        let renderer = ImageRenderer(content: PoemShareCard(poem: poem, style: style))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: PoemShareCard.width, height: nil)
        withAnimation(.smooth) { image = renderer.uiImage }
    }
}
