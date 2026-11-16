import SwiftUI

/// Spec 020 R2: one word that rolls up to the next every few seconds, the rest of the sentence still ("Hear a
/// poem?" → "Hear a speech?"). The old word leaves through the top while the new one rises from below. Reduce Motion
/// cross-fades instead. Font and colour come from the caller.
///
/// Layout comes only from an invisible, still copy of the current word: its width follows the word (so the sentence
/// re-centres smoothly), but its height and baseline never change, so nothing below the line moves while a word
/// rolls. The rolling copies live in an overlay, clipped above and below the line only.
struct RollingWord: View {
    let words: [String]
    /// Draws the word with a leading space, so the gap after the preceding text is a real word space. A trailing
    /// space on that text would not count: a line's width leaves out trailing whitespace.
    var leadingSpace = true
    var interval: Duration = .seconds(2.6)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        Text(label(index))
            .hidden()
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Text(label(index))
                        .fixedSize()
                        .id(index)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            // Clip vertically only; a longer word must not be cut while the width catches up.
            .mask { Rectangle().padding(.horizontal, -400) }
            .task {
                guard words.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(duration: 0.55, bounce: 0.15)) { index = (index + 1) % words.count }
                }
            }
    }

    private func label(_ index: Int) -> String {
        (leadingSpace ? " " : "") + words[index]
    }
}

/// The words both rolling headings cycle through (owner, spec 020): what the app can keep, poems first.
enum RollingWords {
    static let singular = ["poem", "speech", "story", "plan"]
    static let plural = ["poems", "speeches", "stories", "plans"]
}
