import AnamnesisKit
import SwiftUI

/// One capture session in the list (spec 008 R3): date, duration, state, Moments and a first-line preview.
struct CaptureSessionRow: View {
    @Environment(AppEnvironment.self) private var environment
    let session: CaptureSession

    var body: some View {
        let job = environment.transcripts?.state(of: session.spoolSessionID)
        let status = CaptureSessionStatus(session: session, environment: environment)
        let moments = session.sortedMoments
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Spacer()
                Text(CaptureFormat.duration(session.durationSec))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Label(status.label, systemImage: status.systemImage)
                    .foregroundStyle(status.state == .failed ? .red : .secondary)
                if status.state == .transcribed {
                    Text("· \(moments.count) Moment\(moments.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    if session.newMomentCount > 0 {
                        Text("· \(session.newMomentCount) new").foregroundStyle(.tint)
                    }
                }
            }
            .font(.subheadline)
            if case .running(let processed, let audio) = job, let audio, audio > 0 {
                ProgressView(value: min(processed, audio), total: audio)
            }
            if let failure = status.failureText {
                Text(failure).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            if let line = moments.first?.poemText.split(separator: "\n").first {
                Text(String(line)).font(.callout).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// What a session's row and detail show, from the library row, the queue and the capture controller.
struct CaptureSessionStatus {
    let state: CaptureSessionState
    /// This process's job error first, else the one stored from an earlier launch.
    let failureText: String?
    let error: TranscriptionError?

    init(session: CaptureSession, environment: AppEnvironment) {
        let id = session.spoolSessionID
        let jobState = environment.transcripts?.state(of: id)
        let job: CaptureSessionState.Job? = switch jobState {
        case .running: .running
        case .failed: .failed
        case nil: nil
        }
        let manifest = environment.sessions?.sessions.first { $0.id == id }?.manifest
        state = CaptureSessionState(isActive: id == environment.capture.activeSpoolSessionID,
                                    stored: session.state, manifestState: manifest?.state, job: job)
        if case .failed(let error) = jobState {
            self.error = error
            failureText = error.localizedDescription
        } else {
            error = nil
            failureText = state == .failed ? session.failureText ?? "Nothing could be recovered from this capture."
                                           : nil
        }
    }

    var label: String {
        switch state {
        case .capturing: "Capturing"
        case .saved: "Saved, waiting to transcribe"
        case .transcribing: "Transcribing"
        case .transcribed: "Transcribed"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch state {
        case .capturing: "record.circle"
        case .saved: "tray"
        case .transcribing: "waveform"
        case .transcribed: "text.quote"
        case .failed: "exclamationmark.triangle"
        }
    }
}

enum CaptureFormat {
    /// e.g. "4:07"; "–" when unknown.
    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "–" }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    static func seconds(_ value: Double?, digits: Int = 1) -> String {
        value.map { String(format: "%.\(digits)f s", $0) } ?? "–"
    }
}
