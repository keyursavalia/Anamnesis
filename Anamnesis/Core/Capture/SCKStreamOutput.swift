#if canImport(ScreenCaptureKit)
import AnamnesisKit
import CoreMedia
import ScreenCaptureKit

// SPIKE: receives SCK sample buffers. Every output type is registered on `sampleQueue`, so the non-thread-safe
// `AudioIngestPipeline` is only ever touched from that one serial queue. Nothing here hops to the main actor.
nonisolated final class SCKStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let sampleQueue = DispatchQueue(label: "\(AppIdentifiers.appBundleID).sck.samples", qos: .userInitiated)
    private let pipeline: AudioIngestPipeline
    private let onStop: @Sendable (ProbeReport.Stop) -> Void

    init(pipeline: AudioIngestPipeline, onStop: @escaping @Sendable (ProbeReport.Stop) -> Void) {
        self.pipeline = pipeline
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        pipeline.ingest(sampleBuffer, type: Self.bufferType(type))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let error = error as NSError
        onStop(ProbeReport.Stop(
            reason: error.domain == SCStreamErrorDomain ? StreamErrorCode.stopReason(error.code) : .error,
            errorDomain: error.domain,
            errorCode: error.code,
            errorDescription: "\(StreamErrorCode.name(error.code)): \(error.localizedDescription)"))
    }

    private static func bufferType(_ type: SCStreamOutputType) -> ProbeReport.BufferType {
        switch type {
        case .screen: .screen
        case .audio: .audio
        case .microphone: .microphone
        @unknown default: .screen // counted, never analyzed
        }
    }
}
#endif
