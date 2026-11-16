import SwiftUI

// The welcome's moving pictures (spec 016 R8): kept apart from the pages' words. Each stills with Reduce Motion.

/// The app mark with a soft halo that breathes.
struct GlowingMark: View {
    let animates: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Night.glow.opacity(0.35))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .phaseAnimator([false, true]) { halo, wide in
                    halo.scaleEffect(animates && wide ? 1.15 : 0.95).opacity(animates && wide ? 1 : 0.7)
                } animation: { _ in .easeInOut(duration: 2.4) }
            AppMark(size: 112)
        }
    }
}

/// Half-heard lines drifting up and fading: a poem, a speech, a story, a plan (spec 020: the app keeps anything
/// spoken). Public domain (Dickinson, Lincoln, Wordsworth) or written for the app.
struct FloatingVerses: View {
    let animates: Bool

    private struct Line {
        let text: String
        let offset: CGSize
        let delay: Double
    }

    private static let lines = [
        Line(text: "Hope is the thing with feathers", offset: CGSize(width: -70, height: -70), delay: 0),
        Line(text: "Four score and seven years ago", offset: CGSize(width: 60, height: 80), delay: 1.6),
        Line(text: "Once upon a time, by the sea", offset: CGSize(width: 80, height: -100), delay: 3.2),
        Line(text: "First, we leave at dawn", offset: CGSize(width: -80, height: 100), delay: 4.8),
        Line(text: "I wandered lonely as a cloud", offset: CGSize(width: 0, height: 10), delay: 6.4)
    ]

    var body: some View {
        ZStack {
            ForEach(Self.lines.indices, id: \.self) { index in
                let line = Self.lines[index]
                DriftingLine(text: line.text, delay: line.delay, animates: animates)
                    .offset(line.offset)
            }
        }
        .accessibilityHidden(true)
    }
}

struct DriftingLine: View {
    let text: String
    let delay: Double
    let animates: Bool
    @State private var started = false

    private static let period = 8.0

    var body: some View {
        // Inserted only after its delay, so each line's cycle really starts later (a phase animator starts when it
        // appears; hiding it until the delay would leave every line rising in step). The hidden copy keeps the layout.
        label
            .hidden()
            .overlay {
                if started {
                    label
                        .phaseAnimator([0.0, 1.0]) { line, progress in
                            let rise: CGFloat = -40 * progress
                            let fade: Double = animates ? sin(progress * .pi) * 0.32 : 0
                            line.offset(y: rise).opacity(fade)
                        } animation: { progress in
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

    private var label: some View {
        Text(text)
            .font(.system(.callout, design: .serif))
            .italic()
            .foregroundStyle(Night.cream)
            .fixedSize()
    }
}

/// A slice of Control Center: three dim tiles and *Transcribe*, which a fingertip taps; it lights up and listens.
struct ControlCenterMock: View {
    let animates: Bool

    private enum Beat: CaseIterable {
        case idle, press, lit, hold
    }

    var body: some View {
        ZStack {
            Circle().fill(Night.glow.opacity(0.22)).frame(width: 220, height: 220).blur(radius: 50)
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    tile("airplane")
                    tile("wifi")
                }
                GridRow {
                    tile("moon.fill")
                    captureTile
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Control Center with the Transcribe control turning on")
    }

    private func tile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(Night.cream.opacity(0.55))
            .frame(width: 84, height: 84)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 24, style: .continuous))
    }

    private var captureTile: some View {
        Color.clear
            .frame(width: 84, height: 84)
            .phaseAnimator(Beat.allCases) { base, beat in
                base.overlay { CaptureTileFace(beat: beat, animates: animates) }
            } animation: { beat in
                switch beat {
                case .idle: .easeInOut(duration: 0.4).delay(1.2)
                case .press: .spring(duration: 0.3)
                case .lit: .spring(duration: 0.4, bounce: 0.4)
                case .hold: .easeInOut(duration: 0.3).delay(2.2)
                }
            }
    }

    private struct CaptureTileFace: View {
        let beat: Beat
        let animates: Bool

        var body: some View {
            let isOn = animates ? (beat == .lit || beat == .hold) : true
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.title2.weight(.semibold))
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isOn && animates)
                    Text(isOn ? "Listening" : "Transcribe")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(isOn ? Night.ink : Night.cream)
                .frame(width: 84, height: 84)
                .background(isOn ? AnyShapeStyle(Night.glow) : AnyShapeStyle(.ultraThinMaterial),
                            in: .rect(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Night.glow.opacity(isOn ? 0 : 0.8), lineWidth: 1.5)
                }
                .scaleEffect(beat == .press ? 0.9 : 1)
                if animates {
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .offset(x: 6, y: 6)
                        .opacity(beat == .press ? 1 : 0)
                        .scaleEffect(beat == .press ? 1 : 1.4)
                }
            }
        }
    }
}

/// A mesh of warm light that drifts slowly; its colours shift with the page (ember, fire, sage).
struct AuroraBackground: View {
    let page: Int
    let animates: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animates)) { timeline in
            MeshGradient(width: 3, height: 3, points: points(timeline.date.timeIntervalSinceReferenceDate),
                         colors: Self.colors(page))
        }
        .animation(.smooth(duration: 1.2), value: page)
        .ignoresSafeArea()
    }

    private func points(_ time: Double) -> [SIMD2<Float>] {
        func wobble(_ phase: Double, _ amount: Double = 0.08) -> Float {
            animates ? Float(sin(time * 0.35 + phase) * amount) : 0
        }
        return [
            [0, 0], [0.5 + wobble(0), 0], [1, 0],
            [0, 0.5 + wobble(1)], [0.5 + wobble(2, 0.12), 0.45 + wobble(3, 0.12)], [1, 0.5 + wobble(4)],
            [0, 1], [0.5 + wobble(5), 1], [1, 1]
        ]
    }

    /// Built once: the timeline asks for them every frame, and each `Color(light:dark:)` is a new dynamic `UIColor`.
    private static let palettes: [[Color]] = {
        let ink = Night.base
        let plum = Color(light: 0x2A1A2E, dark: 0x2A1A2E)
        let ember = Color(light: 0x8E3018, dark: 0x8E3018)
        let fire = Color(light: 0xC24F30, dark: 0xC24F30)
        let amber = Color(light: 0x6B4A1A, dark: 0x6B4A1A)
        let moss = Color(light: 0x24382B, dark: 0x24382B)
        let fern = Color(light: 0x3E5E47, dark: 0x3E5E47)
        return [
            [ink, plum, ink, amber, ember, plum, ink, ink, ink],
            [ink, ember, plum, plum, fire, ink, ink, amber, ink],
            [ink, moss, ink, plum, fern, ink, ink, ink, moss]
        ]
    }()

    private static func colors(_ page: Int) -> [Color] {
        palettes[min(max(page, 0), palettes.count - 1)]
    }
}

struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Night.cream : Night.cream.opacity(0.25))
                    .frame(width: index == current ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.35), value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
