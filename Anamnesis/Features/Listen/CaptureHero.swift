import SwiftUI

/// The one big control on the Listen screen (spec 015 R2): a warm orb that breathes while idle, sends out rings
/// while listening, and says in one line what happens next.
struct CaptureHero: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capture = environment.capture
        let phase = capture.phase
        VStack(spacing: 10) {
            Button {
                toggle()
            } label: {
                Orb(phase: phase, isAvailable: capture.isPickerAvailable, animates: !reduceMotion)
            }
            .buttonStyle(OrbButtonStyle())
            .disabled(!capture.isPickerAvailable && !capture.isCapturing)
            .accessibilityLabel(capture.isCapturing ? "Stop listening" : "Start listening")
            .accessibilityHint(capture.isCapturing ? "Saves the capture and transcribes it"
                                                   : "Opens the system sheet to share the sound of other apps")
            .sensoryFeedback(trigger: phase) { old, new in
                switch (old, new) {
                case (_, .capturing): .start
                case (.capturing, .idle): .stop
                default: nil
                }
            }

            caption(phase, isAvailable: capture.isPickerAvailable)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .animation(.smooth, value: phase)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func caption(_ phase: CaptureController.Phase, isAvailable: Bool) -> some View {
        VStack(spacing: 8) {
            switch phase {
            case .idle:
                Text("Hear a poem?").font(Theme.display(.title))
                Text(isAvailable
                     ? "Tap, choose **Share Entire Screen**, then go back to your reel."
                     : "Capturing needs an iPhone or iPad with screen sharing.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
            case .choosing:
                Text("Almost there").font(Theme.display(.title))
                Text("Choose **Share Entire Screen**, then tap **Start**.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
            case .capturing(let since):
                Text(since, style: .timer)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .accessibilityLabel("Listening")
                Text("Listening. Play your reel; come back and tap to stop. Poems go straight to your Library.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func toggle() {
        let capture = environment.capture
        if capture.isCapturing {
            Task { await capture.stop() }
        } else {
            try? capture.start(label: "listen")
        }
    }
}

/// The orb itself. Motion comes from phase animations, which the render server interpolates: `body` runs once
/// per phase, not per frame (a `TimelineView` here re-ran it 30 times a second while idle). Reduce Motion, or no
/// capture support, leaves it still.
private struct Orb: View {
    let phase: CaptureController.Phase
    let isAvailable: Bool
    let animates: Bool

    private static let size: CGFloat = 168
    private var isCapturing: Bool { if case .capturing = phase { true } else { false } }
    private var breathes: Bool { animates && isAvailable && !isCapturing }

    var body: some View {
        ZStack {
            if isCapturing && animates {
                ForEach(0..<3, id: \.self) { index in
                    Ring(size: Self.size, delay: Double(index) * Ring.period / 3)
                }
            }
            core.phaseAnimator([false, true]) { content, inhaled in
                content.scaleEffect(breathes && inhaled ? 1.025 : 1)
            } animation: { _ in
                .easeInOut(duration: 1.85)
            }
        }
        .frame(width: Self.size * 1.5, height: Self.size * 1.5)
    }

    private var core: some View {
        ZStack {
            Circle()
                .fill(isAvailable ? AnyShapeStyle(LinearGradient(colors: [Theme.emberFill, Theme.emberDeep],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Theme.sunken))
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1).padding(6)
                }
                .shadow(color: isAvailable ? Theme.ember.opacity(0.35) : .clear, radius: 28, y: 12)
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(isAvailable ? Color.white : Theme.inkSecondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating,
                              isActive: phase == .choosing && animates)
        }
        .frame(width: Self.size, height: Self.size)
    }

    private var symbol: String {
        switch phase {
        case .idle, .choosing: "waveform"
        case .capturing: "stop.fill"
        }
    }
}

/// One ring that grows and fades, forever; three with staggered starts read as a steady pulse.
private struct Ring: View {
    static let period = 2.6
    let size: CGFloat
    let delay: Double
    @State private var started = false

    var body: some View {
        Circle()
            .stroke(Theme.ember, lineWidth: 1.5)
            .frame(width: size, height: size)
            .opacity(started ? 1 : 0)
            .phaseAnimator([0.0, 1.0]) { content, progress in
                let scale: CGFloat = 1 + progress * 0.45
                let opacity: Double = (1 - progress) * 0.55
                content.scaleEffect(scale).opacity(opacity)
            } animation: { progress in
                // Grow over the period, then snap back unseen (opacity is 0 at the end).
                let duration: Double = progress == 1 ? Self.period : 0
                return .linear(duration: duration)
            }
            .task {
                try? await Task.sleep(for: .seconds(delay))
                started = true
            }
    }
}

private struct OrbButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: configuration.isPressed)
    }
}
