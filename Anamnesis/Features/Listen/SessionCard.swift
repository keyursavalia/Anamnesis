import AnamnesisKit
import SwiftUI

/// One recording on the Transcribe screen (spec 015 R2; spec 016 R1): when, how long, the first transcript, and
/// where it stands. A finished recording's transcripts are already in the library; a failed one offers its fix right
/// here, since there is no review screen any more. The list computes `status` once per row and passes it in.
struct SessionCard: View {
    @Environment(AppEnvironment.self) private var environment
    let session: CaptureSession
    let status: CaptureSessionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(CaptureFormat.when(session.startedAt))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Label(CaptureFormat.duration(session.durationSec), systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
            }
            if let line = session.sortedMoments.lazy.compactMap(\.poem).first?.displayTitle {
                Text("“\(line)”")
                    .font(Theme.verse(.title3))
                    .italic()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                pill
                Spacer()
                if opensLibrary {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                }
            }
            if let progress = status.progress {
                ProgressView(value: progress).tint(Theme.ember)
            }
            if let failure = status.failureText {
                Text(failure).font(.caption).foregroundStyle(Theme.danger).lineLimit(3)
                recovery
            }
        }
        .card()
        .contentShape(.rect(cornerRadius: Theme.cornerRadius))
    }

    /// Finished with transcripts: tapping the card goes to the library, where they are.
    var opensLibrary: Bool { status.state == .transcribed && session.keptPoemCount > 0 }

    @ViewBuilder
    private var pill: some View {
        switch status.state {
        case .capturing:
            Pill(text: "Listening", systemImage: "waveform", filled: true)
        case .saved:
            if environment.transcripts?.isWaitingForModel == true {
                Pill(text: "Waiting for speech model", systemImage: "arrow.down.circle", tint: Theme.inkSecondary)
            } else {
                Pill(text: "Waiting to transcribe", systemImage: "hourglass", tint: Theme.inkSecondary)
            }
        case .transcribing:
            Pill(text: status.progress.map { "Transcribing \(Int($0 * 100))%" } ?? "Transcribing",
                 systemImage: "text.bubble")
        case .failed:
            Pill(text: "Couldn’t transcribe", systemImage: "exclamationmark.triangle", tint: Theme.danger)
        case .transcribed:
            let kept = session.keptPoemCount
            if session.moments.isEmpty {
                Pill(text: "No speech heard", systemImage: "speaker.slash", tint: Theme.inkSecondary)
            } else if kept == 0 {
                Pill(text: "Nothing kept", systemImage: "books.vertical", tint: Theme.inkSecondary)
            } else {
                Pill(text: kept == 1 ? "1 transcript in your library" : "\(kept) transcripts in your library",
                     systemImage: "checkmark", tint: Theme.sage)
            }
        }
    }

    /// The fixes the review screen used to offer (spec 008 R6).
    @ViewBuilder
    private var recovery: some View {
        let id = session.spoolSessionID
        if case .modelNotInstalled = status.error {
            Button("Download speech model", systemImage: "arrow.down.circle") {
                Task { await environment.transcripts?.installModelAndRetry(id) }
            }
            .buttonStyle(ProminentButtonStyle())
        } else if !session.audioDeleted {
            Button("Try again", systemImage: "arrow.clockwise") {
                Task { await environment.transcripts?.retry(id) }
            }
            .buttonStyle(ProminentButtonStyle())
        }
    }
}
