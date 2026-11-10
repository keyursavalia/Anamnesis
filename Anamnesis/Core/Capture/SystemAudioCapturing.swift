import AnamnesisKit
import Foundation

/// Host-side contract shared by capture backends (ARCHITECTURE §3.1). Starting differs per backend
/// (SCK presents a picker; ReplayKit is started from the system broadcast picker), so it is not part of the protocol.
protocol SystemAudioCapturing: AnyObject {
    var backend: ProbeReport.Backend { get }
    var events: AsyncStream<CaptureEvent> { get }
    var isCapturing: Bool { get }
    /// Stops capture and finalizes the run's report; nil if nothing was running.
    func stop() async -> ProbeRun?
}

/// A finished (or interrupted) probe run on disk.
nonisolated struct ProbeRun: Sendable, Identifiable {
    var id: URL { directory }
    let directory: URL
    let reportURL: URL
    let rawDumpURL: URL?
    let report: ProbeReport
}

nonisolated enum CaptureEvent: Sendable {
    case pickerPresented(style: String)
    case pickerCancelled
    case pickerFailed(String)
    /// A content filter arrived. `unsolicited`: we had not presented the picker (system UI started sharing).
    case filterReceived(unsolicited: Bool, forExistingStream: Bool)
    case started
    case startFailed(String)
    case stopped(ProbeRun)
}

enum CaptureError: Error, LocalizedError {
    case pickerUnavailable
    case alreadyCapturing
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .pickerUnavailable: "The screen-sharing picker is not available on this device."
        case .alreadyCapturing: "A capture is already running."
        case .storage(let message): "Could not prepare the run folder: \(message)"
        }
    }
}

/// `SCStreamErrorDomain` codes (APPLE_APIS §3.4), kept as plain ints so this compiles where SCK is absent.
nonisolated enum StreamErrorCode {
    static let domain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"

    private static let names: [Int: String] = [
        -3801: "userDeclined", -3802: "failedToStart", -3803: "missingEntitlements",
        -3804: "failedApplicationConnectionInvalid", -3805: "failedApplicationConnectionInterrupted",
        -3811: "internalError", -3817: "userStopped", -3818: "failedToStartAudioCapture",
        -3819: "failedToStopAudioCapture", -3820: "failedToStartMicrophoneCapture", -3821: "systemStoppedStream",
        -3822: "insufficientStorage", -3823: "notSupported", -3824: "missingBackgroundMode"
    ]

    static func name(_ code: Int) -> String {
        names[code] ?? "unknown"
    }

    /// How a stream error ends a run in the report.
    static func stopReason(_ code: Int) -> ProbeReport.StopReason {
        switch code {
        case -3817: .user          // stopped from the system indicator
        case -3821: .system
        case -3805: .interruption
        default: .error
        }
    }
}
