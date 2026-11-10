import AnamnesisKit
import Foundation
import Observation
import os

/// Dependency container injected via `.environment`. Services are added here as specs introduce them.
@Observable
final class AppEnvironment {
    /// nil only if Application Support is unwritable; logging then falls back to `os.Logger` alone.
    let fileLog: FileLog?
    /// nil only if Application Support is unavailable; capture then runs without spooling.
    let sessions: SessionIngestor?

    init() {
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileLog: FileLog?
        do {
            guard let support else { throw CocoaError(.fileNoSuchFile) }
            fileLog = try FileLog(directory: support.appending(path: "Logs"))
        } catch {
            Logger(category: .ui).error("FileLog unavailable: \(error.localizedDescription, privacy: .public)")
            fileLog = nil
        }
        self.fileLog = fileLog
        sessions = support.map {
            SessionIngestor(directory: SpoolDirectory(root: $0.appending(path: "Spool")),
                            log: AppLog(category: .spool, fileLog: fileLog))
        }
    }

    func log(_ category: LogCategory) -> AppLog {
        AppLog(category: category, fileLog: fileLog)
    }

    /// Launch and foreground: recover sessions the app died in, except the one being written now.
    func refreshSessions() async {
        await sessions?.refresh(activeSessionIDs: activeSpoolSessionIDs)
    }

    var isCapturing: Bool {
        #if DEBUG && canImport(ScreenCaptureKit)
        sckProbeModel?.isCapturing ?? false
        #else
        false
        #endif
    }

    private var activeSpoolSessionIDs: Set<String> {
        #if DEBUG && canImport(ScreenCaptureKit)
        Set([sckProbeModel?.backend?.spool?.session.id].compactMap(\.self))
        #else
        []
        #endif
    }

    #if DEBUG && canImport(ScreenCaptureKit)
    /// One probe per app session: a capture keeps running while the operator navigates the Lab,
    /// and only one observer is ever registered with the system picker.
    @ObservationIgnored private var sckProbeModel: SCKProbeViewModel?

    func sckProbe() -> SCKProbeViewModel {
        if let sckProbeModel { return sckProbeModel }
        let model = SCKProbeViewModel(environment: self)
        sckProbeModel = model
        return model
    }
    #endif
}
