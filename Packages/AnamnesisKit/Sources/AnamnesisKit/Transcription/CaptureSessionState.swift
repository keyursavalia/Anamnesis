/// What a Captures row shows for one spool session (spec 008 R3).
public enum CaptureSessionState: String, Sendable, Equatable, CaseIterable {
    case capturing, saved, transcribing, transcribed, failed

    /// The transcription queue's in-memory view of a session; nil when it has no job for it.
    public enum Job: Sendable, Equatable {
        case running, failed
    }

    /// A stored transcript wins over a job state; a session being written wins over everything.
    /// `stored` is the library row's state (spec 009); nil before the session reached the store.
    public init(isActive: Bool, stored: StoredSessionState?, manifestState: SpoolManifest.State?, job: Job?) {
        if isActive {
            self = .capturing
        } else if stored == .transcribed {
            self = .transcribed
        } else if job == .running {
            self = .transcribing
        } else if job == .failed || stored == .failed || manifestState == .interrupted {
            self = .failed
        } else {
            self = .saved
        }
    }

    /// The queue picks a session only once it is final, still has audio, and has no transcript yet.
    public static func isTranscribable(isDone: Bool, manifestState: SpoolManifest.State?, hasAudio: Bool,
                                       hasTranscript: Bool) -> Bool {
        guard isDone, hasAudio, !hasTranscript else { return false }
        return manifestState == .finished || manifestState == .recovered
    }
}
