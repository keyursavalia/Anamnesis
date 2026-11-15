#if DEBUG
import AnamnesisKit
import SwiftUI

/// DEBUG timings for a session (spec 008 R8), from the Listen card's context menu since spec 016 removed review.
struct SessionMetricsCard: View {
    let metrics: SessionMetrics
    let session: CaptureSession
    let summary: SpoolSessionSummary?

    var body: some View {
        let capture = metrics.capture
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Metrics (DEBUG)")
            Group {
                LabeledContent("Audio", value: CaptureFormat.seconds(metrics.audioSec))
                LabeledContent("Capture", value: CaptureFormat.seconds(capture?.durationSec))
                LabeledContent("Stopped", value: Self.time(capture?.stoppedAt))
                LabeledContent("Foregrounded", value: Self.time(capture?.foregroundedAt))
                LabeledContent("Transcription", value: "\(Self.time(metrics.transcriptionStartedAt)) → "
                               + Self.time(metrics.readyAt))
                LabeledContent("Job", value: CaptureFormat.seconds(metrics.jobSec))
                LabeledContent("Latency", value: CaptureFormat.seconds(metrics.latencySec))
                LabeledContent("Latency ÷ audio (AC2 ≤ 1)",
                               value: metrics.latencyRatio.map { String(format: "%.3f", $0) } ?? "–")
                LabeledContent("Battery", value: "\(Self.battery(capture?.start)) → \(Self.battery(capture?.stop))")
                LabeledContent("Battery drop (AC3 ≤ 10 %)",
                               value: capture?.batteryDrop.map { String(format: "%.1f %%", $0 * 100) } ?? "–")
                LabeledContent("Thermal", value: "\(capture?.start.thermalState ?? "–") → "
                               + (capture?.stop?.thermalState ?? "–"))
                LabeledContent("Audio kept", value: session.audioDeleted ? "no" : "yes")
                LabeledContent("Failed attempts", value: "\(session.attempts)")
            }
            .font(.footnote)
            if let summary, summary.hasTranscript {
                ShareLink(item: summary.session.transcriptURL) {
                    Label("Export transcript.json", systemImage: "square.and.arrow.up")
                }
                .font(.footnote)
            }
        }
        .card(padding: 16)
    }

    private static func time(_ date: Date?) -> String {
        date?.formatted(date: .omitted, time: .standard) ?? "–"
    }

    private static func battery(_ snapshot: PowerSnapshot?) -> String {
        guard let snapshot else { return "–" }
        let level = snapshot.batteryLevel.map { String(format: "%.0f %%", $0 * 100) } ?? "?"
        return "\(level) \(snapshot.batteryState.rawValue)"
    }
}
#endif
