import AnamnesisKit
import Foundation
import Observation
import os

/// Dependency container injected via `.environment`. Services are added here as specs introduce them.
@Observable
final class AppEnvironment {
    /// nil only if Application Support is unwritable; logging then falls back to `os.Logger` alone.
    let fileLog: FileLog?

    init() {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            fileLog = try FileLog(directory: support.appending(path: "Logs"))
        } catch {
            Logger(category: .ui).error("FileLog unavailable: \(error.localizedDescription, privacy: .public)")
            fileLog = nil
        }
    }

    func log(_ category: LogCategory) -> AppLog {
        AppLog(category: category, fileLog: fileLog)
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
