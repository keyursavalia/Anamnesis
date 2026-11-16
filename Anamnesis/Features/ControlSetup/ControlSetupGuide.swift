import SwiftUI

/// The four steps to add *Transcribe* (spec 015 R9), with a drawn phone that acts each one out in turn. The
/// highlighted step and the drawing advance together; tapping a step jumps to it.
struct ControlSetupGuide: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    static let steps: [LocalizedStringKey] = [
        "Swipe down from the **top-right corner** to open Control Center.",
        "Tap **+** in the top-left corner.",
        "Tap **Add a Control** at the bottom.",
        "Search **Anamnesis** and tap **Transcribe**."
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            MiniPhone(step: step)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.steps.indices, id: \.self) { index in
                    Button {
                        withAnimation(.smooth) { step = index }
                    } label: {
                        GuideStep(number: index + 1, text: Self.steps[index], isCurrent: index == step)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: step) {
            // Hold each step long enough to read it, then move on; Reduce Motion keeps the reader in charge.
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.5)) { step = (step + 1) % Self.steps.count }
        }
    }
}

private struct GuideStep: View {
    let number: Int
    let text: LocalizedStringKey
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(.caption, design: .serif, weight: .bold))
                .foregroundStyle(isCurrent ? Color.white : Theme.ember)
                .frame(width: 22, height: 22)
                .background(isCurrent ? AnyShapeStyle(Theme.emberFill) : AnyShapeStyle(Theme.ember.opacity(0.12)),
                            in: .circle)
            Text(text)
                .font(.footnote)
                .foregroundStyle(isCurrent ? Theme.ink : Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .contentShape(.rect)
    }
}

/// A schematic phone: a reel, then Control Center, then the edit and add-control screens.
private struct MiniPhone: View {
    let step: Int

    private static let width: CGFloat = 112
    private static let height: CGFloat = 220

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(step == 0 ? Theme.sunken : Color(white: 0.12))
            content
                .padding(10)
                .padding(.top, 14)
                .transition(.opacity)
                .id(step)
            Capsule().fill(.black).frame(width: 34, height: 10).frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 7)
        }
        .frame(width: Self.width, height: Self.height)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: swipe
        case 1: controlCenter(highlightPlus: true)
        case 2: addControl
        default: search
        }
    }

    /// A reel playing, and a finger dragging down from the top-right corner.
    private var swipe: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.hairline).frame(height: 120)
                    .overlay { Image(systemName: "play.fill").foregroundStyle(Theme.inkSecondary) }
                ForEach(0..<2, id: \.self) { _ in
                    Capsule().fill(Theme.hairline).frame(height: 6)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            SwipeHint()
        }
    }

    private func controlCenter(highlightPlus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "plus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(highlightPlus ? AnyShapeStyle(Theme.emberFill) : AnyShapeStyle(.white.opacity(0.2)),
                            in: .circle)
                .modifier(Pulse(isActive: highlightPlus))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 2), spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.16)).frame(height: 38)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var addControl: some View {
        ZStack(alignment: .bottom) {
            controlCenter(highlightPlus: false).opacity(0.35)
            Text("Add a Control")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.emberFill, in: .capsule)
                .modifier(Pulse(isActive: true))
                .padding(.bottom, 6)
        }
    }

    private var search: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Text("Anamnesis")
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14), in: .capsule)
            VStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.emberFill, in: .rect(cornerRadius: 12))
                    .modifier(Pulse(isActive: true))
                Text("Transcribe")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
    }
}

/// A fingertip that slides down from the corner, over and over.
private struct SwipeHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Theme.ember.opacity(0.85))
                .frame(width: 18, height: 18)
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.ember)
        }
        .offset(y: down ? 60 : -6)
        .opacity(down ? 0.2 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { down = true }
        }
    }
}

/// A soft ring that draws the eye to the thing to tap.
private struct Pulse: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .background {
                if isActive {
                    Capsule().stroke(Theme.ember, lineWidth: 2)
                        .padding(-4)
                        .scaleEffect(isPulsing ? 1.25 : 1)
                        .opacity(isPulsing ? 0 : 0.9)
                }
            }
            .onAppear {
                guard isActive, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { isPulsing = true }
            }
    }
}
