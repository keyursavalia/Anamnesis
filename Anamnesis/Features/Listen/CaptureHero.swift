import SwiftUI

/// The one big control on the Transcribe screen (spec 015 R2): a warm orb that breathes while idle and sends out rings
/// while listening, a line on what happens next, and a three-step track that lights the step the user is on.
struct CaptureHero: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capture = environment.capture
        let phase = capture.phase
        VStack(spacing: 18) {
            Button {
                toggle()
            } label: {
                Orb(phase: phase, isAvailable: capture.isPickerAvailable, animates: !reduceMotion)
            }
            .buttonStyle(OrbButtonStyle())
            .disabled(!capture.isPickerAvailable && !capture.isCapturing)
            .accessibilityLabel(capture.isCapturing ? "Stop and transcribe"
                                : phase == .choosing ? "Start over" : "Transcribe")
            .accessibilityHint(capture.isCapturing ? "Stops listening and transcribes what was heard"
                               : phase == .choosing ? "Resets if the screen-sharing sheet has closed"
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
                .frame(maxWidth: 340)
                .animation(.smooth, value: phase)

            if capture.isPickerAvailable {
                StepTrack(current: StepTrack.step(for: phase))
                    .animation(.smooth, value: phase)
                // Icon and text hug each other as one centred unit (a `Label` spreads them apart when it wraps).
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "lock.fill").imageScale(.small)
                    Text("Only the sound other apps play, transcribed on this device")
                }
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func caption(_ phase: CaptureController.Phase, isAvailable: Bool) -> some View {
        VStack(spacing: 8) {
            switch phase {
            case .idle:
                // Only the last word rolls (spec 020 R2): poem → speech → story → plan.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Hear a")
                    RollingWord(words: RollingWords.singular).foregroundStyle(Theme.ember)
                    Text("?")
                }
                .font(Theme.display(.title))
                // Full width, so the caption's width never follows the word and the line below never shifts.
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hear a poem, a speech, a story or a plan?")
                .accessibilityAddTraits(.isHeader)
                Text(isAvailable
                     ? "Tap to transcribe. Choose **Share Entire Screen**, then go back to your media."
                     : "Transcribing needs an iPhone or iPad with screen sharing.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
            case .choosing:
                Text("Almost there").font(Theme.display(.title))
                Text("Choose **Share Entire Screen**, then tap **Start**. Closed it? Tap the orb to start over.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
            case .capturing(let since):
                Text(since, style: .timer)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .accessibilityLabel("Listening")
                Text("Listening. Play your media, then come back and tap to transcribe.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    /// While `choosing`, the orb is only reachable once the picker is gone, so a tap then starts over.
    private func toggle() {
        let capture = environment.capture
        if capture.isCapturing {
            Task { await capture.stop() }
        } else if capture.phase == .choosing {
            capture.cancelPendingStart()
        } else {
            try? capture.start(label: "listen")
        }
    }
}

/// Tap → Play → Transcribe as three dots on a line: done steps in sage, the current one filled ember, the rest
/// waiting. Tells a first-timer the whole flow and a returning one where they are.
private struct StepTrack: View {
    let current: Int

    private static let steps: [(symbol: String, title: String)] = [
        ("hand.tap.fill", "Tap the orb"),
        ("play.fill", "Play your media"),
        // The orb's own symbol, as on the control (spec 020 R4).
        ("waveform", "Tap to transcribe")
    ]

    static func step(for phase: CaptureController.Phase) -> Int {
        if case .capturing = phase { 1 } else { 0 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Self.steps.indices, id: \.self) { index in
                let step = Self.steps[index]
                VStack(spacing: 8) {
                    dot(index, symbol: step.symbol)
                    Text(step.title)
                        .font(.caption.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index == current ? Theme.ink : Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1) of 3: \(step.title)")
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
        .background(alignment: .top) { connectors }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .frame(maxWidth: 420)
    }

    private func dot(_ index: Int, symbol: String) -> some View {
        let done = index < current
        let isCurrent = index == current
        return Image(systemName: done ? "checkmark" : symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(done || isCurrent ? Color.white : Theme.inkSecondary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 36, height: 36)
            .background(done ? Theme.sage : isCurrent ? Theme.emberFill : Theme.sunken, in: .circle)
    }

    /// The lines between dots. Columns are equal, so dot centres sit at 1/6, 3/6 and 5/6 of the width and each line
    /// is centred on a column boundary, stopping short of the dots on either side.
    private var connectors: some View {
        GeometryReader { proxy in
            let column = proxy.size.width / CGFloat(Self.steps.count)
            ForEach(1..<Self.steps.count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.sage : Theme.hairline)
                    .frame(width: max(0, column - 48), height: 2)
                    .position(x: column * CGFloat(index), y: 18)
            }
        }
        .frame(height: 36)
        .accessibilityHidden(true)
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
        // The ring is inserted only after its delay: a phase animator starts cycling when it appears, so one that
        // merely stayed hidden until then would run in step with the others and the three would draw as one.
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if started {
                    Circle()
                        .stroke(Theme.ember, lineWidth: 1.5)
                        .phaseAnimator([0.0, 1.0]) { content, progress in
                            let scale: CGFloat = 1 + progress * 0.45
                            let opacity: Double = (1 - progress) * 0.55
                            content.scaleEffect(scale).opacity(opacity)
                        } animation: { progress in
                            // Grow over the period, then snap back unseen (opacity is 0 at the end).
                            let duration: Double = progress == 1 ? Self.period : 0
                            return .linear(duration: duration)
                        }
                }
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
