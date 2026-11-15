import AnamnesisKit
import Foundation

/// What a session's card and review screen show, from the library row, the queue and the capture controller.
struct CaptureSessionStatus {
    let state: CaptureSessionState
    /// This process's job error first, else the one stored from an earlier launch.
    let failureText: String?
    let error: TranscriptionError?
    /// 0…1 while transcribing, when the audio length is known.
    let progress: Double?

    init(session: CaptureSession, environment: AppEnvironment) {
        let id = session.spoolSessionID
        self.init(session: session, environment: environment,
                  manifest: environment.sessions?.sessions.first { $0.id == id }?.manifest)
    }

    /// For lists: the caller looks manifests up once (`manifests(in:)`) instead of once per row.
    init(session: CaptureSession, environment: AppEnvironment, manifest: SpoolManifest?) {
        let id = session.spoolSessionID
        let jobState = environment.transcripts?.state(of: id)
        let job: CaptureSessionState.Job? = switch jobState {
        case .running: .running
        case .failed: .failed
        case nil: nil
        }
        state = CaptureSessionState(isActive: id == environment.capture.activeSpoolSessionID,
                                    stored: session.state, manifestState: manifest?.state, job: job)
        if case .running(let processed, let audio?) = jobState, audio > 0 {
            progress = min(1, processed / audio)
        } else {
            progress = nil
        }
        if case .failed(let error) = jobState {
            self.error = error
            failureText = error.localizedDescription
        } else {
            error = nil
            failureText = state == .failed ? session.failureText ?? "Nothing could be recovered from this capture."
                                           : nil
        }
    }

    /// Spool manifests by session ID, for `init(session:environment:manifest:)`.
    static func manifests(in environment: AppEnvironment) -> [String: SpoolManifest] {
        var byID: [String: SpoolManifest] = [:]
        for summary in environment.sessions?.sessions ?? [] where byID[summary.id] == nil {
            byID[summary.id] = summary.manifest
        }
        return byID
    }

    var label: String {
        switch state {
        case .capturing: "Listening now"
        case .saved: "Waiting to transcribe"
        case .transcribing: "Transcribing"
        case .transcribed: "Transcribed"
        case .failed: "Couldn’t transcribe"
        }
    }

    var systemImage: String {
        switch state {
        case .capturing: "waveform"
        case .saved: "hourglass"
        case .transcribing: "text.bubble"
        case .transcribed: "text.quote"
        case .failed: "exclamationmark.triangle"
        }
    }

    /// Still on its way (or failed): it belongs at the top of the Listen screen.
    func needsAttention(_ session: CaptureSession) -> Bool {
        state != .transcribed
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

    /// "Today, 9:41 PM", "Yesterday, 8:02 AM", "Nov 3, 7:15 PM".
    static func when(_ date: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return String(localized: "Today, \(time)") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday, \(time)") }
        let sameYear = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        let day = sameYear ? date.formatted(.dateTime.month(.abbreviated).day())
                           : date.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(day), \(time)"
    }
}
