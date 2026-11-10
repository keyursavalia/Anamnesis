#if DEBUG
import Foundation
import Observation
import UIKit

// SPIKE: Lab → Environment (spec 000 R7).
@Observable
final class EnvironmentViewModel {
    enum State {
        case idle
        case loading
        case loaded(DeviceEnvironmentReport, exportURL: URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        let report = await DeviceEnvironmentProbe.makeReport()
        do {
            state = .loaded(report, exportURL: try writeExportFile(report))
        } catch {
            state = .failed("Could not write report: \(error.localizedDescription)")
        }
    }

    func copyReport() {
        guard case .loaded(_, let url) = state, let json = try? String(contentsOf: url, encoding: .utf8) else { return }
        UIPasteboard.general.string = json
    }

    /// `ShareLink` needs a file so the owner receives a `.json`, not a text snippet.
    private func writeExportFile(_ report: DeviceEnvironmentReport) throws -> URL {
        let stamp = report.generatedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacing(":", with: "")
        let url = FileManager.default.temporaryDirectory.appending(path: "env-\(stamp).json")
        try report.jsonData().write(to: url, options: .atomic)
        return url
    }
}
#endif
