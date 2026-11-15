import ActivityKit
import AnamnesisKit
import AppIntents
import SwiftUI
import WidgetKit

/// The capture Live Activity (spec 007 R7; restyled to the app's look in spec 017): Lock Screen and Dynamic Island.
/// The app starts and updates it; this only draws the state. Animation comes from symbol effects and the
/// self-ticking timer, never from activity updates (R8).
///
/// Look: the app's night palette (ink background, cream text, ember while live, sage once saved), titles and the
/// timer in New York like the app's headings, and the app mark leading the Lock Screen. Layout follows the HIG:
/// compact leading and trailing read as one piece (symbol + time), minimal is the live symbol, expanded is the
/// compact view enlarged around the camera with one control, and the Lock Screen repeats it at a 16 pt margin.
struct CaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            CaptureLockScreenView(content: CaptureContent(context.state, isStale: context.isStale),
                                  url: context.state.sessionURL)
                .activityBackgroundTint(ActivityPalette.ink.opacity(0.94))
                .activitySystemActionForegroundColor(ActivityPalette.cream)
                .widgetURL(context.state.sessionURL)
        } dynamicIsland: { context in
            let content = CaptureContent(context.state, isStale: context.isStale)
            // Saved is the card the stop alert expands into (spec 018): one row, like Shazam's result. The other
            // phases keep the spec 017 layout. Regions switch on the phase, so the builder needs no branches.
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if content.phase == .saved {
                        SavedCardLeading(content: content)
                    } else {
                        HStack(spacing: 8) {
                            ActivityMark(size: 26)
                            CaptureTitle(content: content,
                                         font: .system(.headline, design: .serif, weight: .semibold))
                        }
                        .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if content.phase == .saved {
                        if let url = context.state.sessionURL {
                            OpenAppPill(url: url)
                                .frame(maxHeight: .infinity)
                                .padding(.trailing, 6)
                        }
                    } else {
                        CaptureValue(content: content, font: .system(.title3, design: .serif))
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if content.phase != .saved {
                        CaptureDetailRow(content: content)
                            .padding(.horizontal, 4)
                            .padding(.top, 6)
                    }
                }
            } compactLeading: {
                CaptureSymbol(content: content)
            } compactTrailing: {
                CaptureCompactTrailing(content: content)
            } minimal: {
                CaptureSymbol(content: content)
            }
            .widgetURL(context.state.sessionURL)
            .keylineTint(content.tint)
        }
    }
}

// MARK: - Content

/// Everything the views say per phase, in one place so every presentation tells the same story. A stale activity
/// (spec 017 R2: the picker was never answered, or the app went away mid-capture) says so instead of pretending.
private struct CaptureContent {
    let phase: CaptureActivityState.Phase
    let startedAt: Date?
    let duration: String?
    let capturedSeconds: Double?
    let isStale: Bool

    init(_ state: CaptureActivityState, isStale: Bool) {
        phase = state.phase
        startedAt = state.startedAt
        duration = state.formattedDuration
        capturedSeconds = state.capturedSeconds
        self.isStale = isStale
    }

    var tint: Color {
        switch phase {
        case .awaitingConsent, .listening: ActivityPalette.ember
        case .saved: ActivityPalette.sage
        case .failed: ActivityPalette.secondary
        }
    }

    var symbol: String {
        switch phase {
        case .awaitingConsent, .listening: "waveform"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    var title: LocalizedStringKey {
        switch phase {
        case .awaitingConsent: isStale ? "Not started" : "Ready"
        case .listening: "Listening"
        case .saved: "Poem captured"
        case .failed: "Nothing captured"
        }
    }

    var detail: LocalizedStringKey {
        switch phase {
        case .awaitingConsent: isStale ? "Tap Capture poem to try again" : "Choose Share Entire Screen to start"
        case .listening: isStale ? "Still listening? Open Anamnesis to check" : "Audio stays on this device"
        case .saved: "Open Anamnesis to add it to your Library"
        case .failed: "No audio was playing"
        }
    }

    var detailSymbol: String? {
        switch phase {
        case .listening: isStale ? "questionmark.circle" : "lock.fill"
        case .saved: "books.vertical.fill"
        case .awaitingConsent, .failed: nil
        }
    }

    var showsStop: Bool { phase == .listening }
    /// "4:07 of audio": the second line of the saved card, where Shazam puts the artist.
    var savedSubtitle: LocalizedStringKey? { duration.map { "\($0) of audio" } }
    var isLive: Bool { phase == .listening && !isStale }
}

// MARK: - Pieces

/// The one symbol: live level bars while listening, dimmed while the picker is up, a mark once ended.
private struct CaptureSymbol: View {
    let content: CaptureContent

    var body: some View {
        Image(systemName: content.symbol)
            .fontWeight(.semibold)
            .foregroundStyle(content.phase == .awaitingConsent ? ActivityPalette.secondary : content.tint)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: content.isLive)
            .accessibilityLabel(content.title)
    }
}

/// Symbol + title, the leading half of the expanded and Lock Screen layouts.
private struct CaptureTitle: View {
    let content: CaptureContent
    let font: Font

    var body: some View {
        HStack(spacing: 6) {
            CaptureSymbol(content: content)
                .font(.subheadline)
            Text(content.title)
                .font(font)
                .foregroundStyle(ActivityPalette.cream)
                .lineLimit(1)
        }
    }
}

/// The live value: elapsed time while listening, the captured length once saved.
private struct CaptureValue: View {
    let content: CaptureContent
    let font: Font

    var body: some View {
        Group {
            switch content.phase {
            case .listening:
                if let startedAt = content.startedAt { CaptureTimer(startedAt: startedAt) }
            case .saved:
                if let duration = content.duration {
                    Text(duration)
                        .accessibilityLabel(Text(Duration.seconds(content.capturedSeconds ?? 0)
                            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))))
                }
            case .awaitingConsent, .failed:
                EmptyView()
            }
        }
        .font(font.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(content.tint)
    }
}

/// `Text(timerInterval:)` takes all the width it is offered; sizing it to a "00:00" template keeps it snug to the
/// camera and the trailing edge aligned. Ticks on its own, with no activity update per second (R8).
private struct CaptureTimer: View {
    let startedAt: Date

    var body: some View {
        Text(verbatim: "00:00")
            .hidden()
            .overlay(alignment: .trailing) {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityLabel("Elapsed time")
    }
}

/// Compact trailing: the same value as expanded, in the same tint. Dropped where the island is limited in width
/// (iOS 27 landscape), so only the symbol remains.
private struct CaptureCompactTrailing: View {
    let content: CaptureContent
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimitedInWidth

    var body: some View {
        if isLimitedInWidth {
            EmptyView()
        } else if content.phase == .awaitingConsent {
            Text(content.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ActivityPalette.secondary)
        } else {
            CaptureValue(content: content, font: .system(.subheadline, design: .serif))
        }
    }
}

/// Detail line on the leading side, the single control (Stop) on the trailing side.
private struct CaptureDetailRow: View {
    let content: CaptureContent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CaptureDetail(content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
            if content.showsStop {
                CaptureStopButton()
            }
        }
    }
}

private struct CaptureDetail: View {
    let content: CaptureContent

    var body: some View {
        Group {
            if let symbol = content.detailSymbol {
                Label(content.detail, systemImage: symbol)
            } else {
                Text(content.detail)
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(ActivityPalette.secondary)
        .lineLimit(2)
    }
}

/// Stop only while listening: it cannot dismiss the picker, so a confirm after it still started a capture (F-052).
/// A filled ember capsule like the app's main buttons.
private struct CaptureStopButton: View {
    var body: some View {
        Button(intent: StopCaptureIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ActivityPalette.emberFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Stops the capture and saves it")
    }
}

// MARK: - Saved card (spec 018)

/// The mark where Shazam shows artwork, then the title and the length in two lines.
private struct SavedCardLeading: View {
    let content: CaptureContent

    var body: some View {
        HStack(spacing: 12) {
            ActivityMark(size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(ActivityPalette.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let subtitle = content.savedSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ActivityPalette.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The tinted pill, like Shazam's Music button: the app's "A" and "Open", ember on a translucent ember capsule.
/// A link, so it opens the app on the capture (which then transcribes it) without running an intent. A saved
/// capture always has a session, so the link always has a target.
private struct OpenAppPill: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Text(verbatim: "A")
                    .font(.system(.subheadline, design: .serif, weight: .bold))
                    .italic()
                Text("Open")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ActivityPalette.ember)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(ActivityPalette.emberFill.opacity(0.28), in: .capsule)
        }
        .accessibilityLabel("Open Anamnesis")
    }
}

// MARK: - Lock Screen

/// The mark, title and detail on the leading side; the time and Stop on the trailing side. About 80 pt tall, well
/// under the Lock Screen's ~160 pt.
private struct CaptureLockScreenView: View {
    let content: CaptureContent
    let url: URL?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ActivityMark(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                CaptureTitle(content: content, font: .system(.headline, design: .serif, weight: .semibold))
                CaptureDetail(content: content)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                CaptureValue(content: content, font: .system(.title2, design: .serif))
                if content.showsStop { CaptureStopButton() }
                if content.phase == .saved, let url { OpenAppPill(url: url) }
            }
        }
        .padding(16)
    }
}

// MARK: - Previews

private let previewStart = Date().addingTimeInterval(-127)

#Preview("Lock Screen", as: .content, using: CaptureActivityAttributes()) {
    CaptureLiveActivity()
} contentStates: {
    CaptureActivityState.awaitingConsent
    CaptureActivityState.listening(since: previewStart, sessionID: "preview")
    CaptureActivityState.stopped(sessionID: "preview", capturedSeconds: 247)
    CaptureActivityState.stopped(sessionID: nil, capturedSeconds: 0)
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: CaptureActivityAttributes()) {
    CaptureLiveActivity()
} contentStates: {
    CaptureActivityState.listening(since: previewStart, sessionID: "preview")
    CaptureActivityState.stopped(sessionID: "preview", capturedSeconds: 247)
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: CaptureActivityAttributes()) {
    CaptureLiveActivity()
} contentStates: {
    CaptureActivityState.listening(since: previewStart, sessionID: "preview")
}
