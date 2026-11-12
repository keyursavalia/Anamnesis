#if DEBUG && canImport(ScreenCaptureKit)
import AnamnesisKit
import SwiftUI

// SPIKE: Lab → Capture (spec 005 rungs 1–2). Where the Control Center control lands; measures tap → first buffer.
struct CaptureLaunchView: View {
    @Bindable var model: SCKProbeViewModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                if model.isCapturing {
                    Button("Stop", systemImage: "stop.circle.fill", role: .destructive) {
                        Task { await model.stop() }
                    }
                } else {
                    Button("Capture poem", systemImage: "record.circle") { start() }
                        .disabled(!model.isPickerAvailable)
                }
                if let error = model.lastError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            launchSection
            Section("Events") {
                ForEach(model.eventLines.prefix(8), id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        }
        .navigationTitle("Capture")
        .task { await model.pollLive() }
        .onChange(of: AutoPresentTrigger(id: environment.launchRequest?.id, phase: scenePhase), initial: true) {
            autoPresentIfPending()
        }
        .onChange(of: model.live?.firstBuffer?.timeToFirstBufferSec, initial: true) { recordTimingIfPending() }
    }

    @ViewBuilder
    private var launchSection: some View {
        Section("Launch") {
            if let request = environment.launchRequest {
                let timing = Timing(request: request, report: model.live ?? model.lastRun?.report)
                LabeledContent("Rung", value: "\(request.rung)")
                LabeledContent("Tap → app", value: Self.format(timing.tapToApp))
                LabeledContent("App → picker requested", value: Self.format(timing.appToStart))
                LabeledContent("Picker requested → first buffer", value: Self.format(timing.startToFirstBuffer))
                LabeledContent("Tap → first buffer", value: Self.format(timing.tapToFirstBuffer))
            } else {
                Text("Opened from the Lab, not from the control.").foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        environment.launchRequest?.startRequestedAt = Date()
        // Always relabel: a label left over from the previous launch mislabelled a rung-2 run (F-029).
        if let request = environment.launchRequest { model.settings.runLabel = "launch-rung\(request.rung)" }
        model.start()
    }

    /// Rung 2: present once per request, only when the scene is active (presenting during launch may fail).
    private func autoPresentIfPending() {
        guard scenePhase == .active, environment.launchRequest?.autoPresentPending == true else { return }
        environment.launchRequest?.autoPresentPending = false
        guard !model.isCapturing else { return }
        start()
    }

    /// Writes the timings into the run's report once the first buffer of a run started after this launch arrives.
    private func recordTimingIfPending() {
        guard let request = environment.launchRequest, request.timingPending, let live = model.live,
              live.startedAt >= request.receivedAt else { return }
        let timing = Timing(request: request, report: live)
        guard timing.firstBufferAt != nil else { return }
        environment.launchRequest?.timingPending = false
        model.addNote("launch rung=\(request.rung) tap→app=\(Self.format(timing.tapToApp)) "
                      + "app→start=\(Self.format(timing.appToStart)) "
                      + "start→firstBuffer=\(Self.format(timing.startToFirstBuffer)) "
                      + "tap→firstBuffer=\(Self.format(timing.tapToFirstBuffer))")
    }

    private static func format(_ seconds: Double?) -> String {
        seconds.map { String(format: "%.2f s", $0) } ?? "—"
    }
}

private struct AutoPresentTrigger: Equatable {
    let id: UUID?
    let phase: ScenePhase
}

private struct Timing {
    let request: LaunchRequest
    let firstBufferAt: Date?

    init(request: LaunchRequest, report: ProbeReport?) {
        self.request = request
        // Only a run that began after this launch counts.
        if let report, report.startedAt >= request.receivedAt, let first = report.firstBuffer {
            firstBufferAt = report.startedAt.addingTimeInterval(first.timeToFirstBufferSec)
        } else {
            firstBufferAt = nil
        }
    }

    var tapToApp: Double? { request.link.tappedAt.map { request.receivedAt.timeIntervalSince($0) } }
    var appToStart: Double? { request.startRequestedAt.map { $0.timeIntervalSince(request.receivedAt) } }
    var startToFirstBuffer: Double? {
        guard let start = request.startRequestedAt, let firstBufferAt else { return nil }
        return firstBufferAt.timeIntervalSince(start)
    }
    var tapToFirstBuffer: Double? {
        guard let tap = request.link.tappedAt, let firstBufferAt else { return nil }
        return firstBufferAt.timeIntervalSince(tap)
    }
}
#endif
