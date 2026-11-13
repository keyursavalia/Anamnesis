import ActivityKit
import AnamnesisKit
import AppIntents
import SwiftUI
import WidgetKit

/// The capture Live Activity (spec 007 R7): Lock Screen and Dynamic Island. The app starts and updates it; this only
/// draws the state. Animation comes from symbol effects, never from activity updates (R8).
///
/// Layout follows the HIG (Live Activities, rev. 2026-10): compact leading and trailing read as one piece of live
/// information (waveform + elapsed time, one tint, Voice Memos-like); minimal shows the live waveform, not a logo;
/// expanded is the compact view enlarged and wrapped around the camera, with one control; the Lock Screen repeats the
/// expanded layout at the standard 14 pt margin.
struct CaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            CaptureLockScreenView(content: CaptureContent(context.state))
                .widgetURL(context.state.sessionURL)
        } dynamicIsland: { context in
            let content = CaptureContent(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CaptureTitle(content: content, font: .headline)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptureValue(content: content, font: .title3)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CaptureDetailRow(content: content)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
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

/// Everything the views say per phase, in one place so every presentation tells the same story.
private struct CaptureContent {
    let phase: CaptureActivityState.Phase
    let startedAt: Date?
    let duration: String?

    init(_ state: CaptureActivityState) {
        phase = state.phase
        startedAt = state.startedAt
        duration = state.formattedDuration
    }

    var tint: Color {
        phase == .failed ? .secondary : .accentColor
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
        case .awaitingConsent: "Ready"
        case .listening: "Listening"
        case .saved: "Saved"
        case .failed: "Nothing captured"
        }
    }

    var detail: LocalizedStringKey {
        switch phase {
        case .awaitingConsent: "Confirm screen sharing to start"
        case .listening: "Audio stays on this device"
        case .saved: "Open Anamnesis to transcribe"
        case .failed: "No audio was playing"
        }
    }

    /// Lock icon only where the line is the privacy promise.
    var detailSymbol: String? { phase == .listening ? "lock.fill" : nil }

    var showsStop: Bool { phase == .listening }
}

// MARK: - Pieces

/// The one symbol: live level bars while listening, dimmed while the picker is up, a mark once ended.
private struct CaptureSymbol: View {
    let content: CaptureContent

    var body: some View {
        Image(systemName: content.symbol)
            .fontWeight(.semibold)
            .foregroundStyle(content.phase == .awaitingConsent
                             ? AnyShapeStyle(.secondary) : AnyShapeStyle(content.tint))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: content.phase == .listening)
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
            Text(content.title)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .font(font)
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
                if let duration = content.duration { Text(duration) }
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
            Text("Ready")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            CaptureValue(content: content, font: .subheadline)
        }
    }
}

/// Detail line on the leading side, the single control (Stop) on the trailing side.
private struct CaptureDetailRow: View {
    let content: CaptureContent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let symbol = content.detailSymbol {
                    Label(content.detail, systemImage: symbol)
                } else {
                    Text(content.detail)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if content.showsStop {
                CaptureStopButton(tint: content.tint)
            }
        }
    }
}

/// Stop only while listening: it cannot dismiss the picker, so a confirm after it still started a capture (F-052).
private struct CaptureStopButton: View {
    let tint: Color

    var body: some View {
        Button(intent: StopCaptureIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(tint.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }
}

// MARK: - Lock Screen

/// The expanded layout at the standard 14 pt Lock Screen margin; height follows the content.
private struct CaptureLockScreenView: View {
    let content: CaptureContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                CaptureTitle(content: content, font: .headline)
                Spacer(minLength: 8)
                CaptureValue(content: content, font: .title2)
            }
            CaptureDetailRow(content: content)
        }
        .padding(14)
        .activitySystemActionForegroundColor(.secondary)
    }
}
