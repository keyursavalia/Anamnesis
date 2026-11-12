#if DEBUG
import AnamnesisKit
import SwiftUI

// SPIKE: one Test B run: aggregates per config × category, per-clip WER, export (spec 004 R7, R9).
struct EvalRunView: View {
    @Bindable var model: EvalViewModel
    let runID: String
    @State private var exportURLs: [URL] = []

    var body: some View {
        if let run = model.run(id: runID) {
            List {
                Section("Run") {
                    LabeledContent("Jobs", value: "\(run.results.count)/\(run.totalJobs)")
                    LabeledContent("Device · OS", value: "\(run.device.modelIdentifier) · \(run.device.osVersion) "
                                   + "(\(run.device.osBuild))")
                    LabeledContent("App", value: run.appVersion)
                    if run.id != model.activeRunID, !run.pendingJobs.isEmpty {
                        Button("Resume", systemImage: "play.circle") { model.resume(run) }.disabled(model.isRunning)
                    }
                    if !exportURLs.isEmpty {
                        ShareLink(items: exportURLs) { Label("Export CSV + JSON", systemImage: "square.and.arrow.up") }
                    }
                }
                summarySection(run)
                clipsSection(run)
            }
            .navigationTitle(run.sweep)
            .task(id: run.results.count + run.ratings.count) { exportURLs = model.exportURLs(run) }
        } else {
            ContentUnavailableView("Run not found", systemImage: "questionmark.folder")
        }
    }

    private func summarySection(_ run: EvalRun) -> some View {
        Section("Aggregates (WER median · mean · min–max)") {
            ForEach(Array(EvalReport.summaries(run).enumerated()), id: \.offset) { _, summary in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.configName) · \(summary.category)").font(.subheadline.bold())
                    Text(Self.describe(summary)).font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func clipsSection(_ run: EvalRun) -> some View {
        Section("Clips") {
            ForEach(run.clips) { clip in
                NavigationLink {
                    EvalClipView(model: model, runID: runID, clip: clip)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(clip.id) · \(clip.category ?? "?")").font(.subheadline)
                        Text(run.configs.map { config in
                            "\(config.name) \(Self.cell(run.result(clipID: clip.id, configName: config.name)))"
                        }.joined(separator: " · "))
                        .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    static func cell(_ result: EvalResult?) -> String {
        guard let result else { return "–" }
        if result.error != nil { return "error" }
        if let wer = result.scores?.wer?.wer { return percent(wer) }
        if let rate = result.scores?.hallucination?.textSecondsPerMinute { return String(format: "%.1f s/min", rate) }
        return "n/a"
    }

    static func describe(_ summary: EvalSummary) -> String {
        var parts = ["\(summary.jobs) jobs" + (summary.failures > 0 ? " (\(summary.failures) failed)" : "")]
        if let wer = summary.wer {
            parts.append("WER \(percent(wer.median)) · \(percent(wer.mean)) · \(percent(wer.min))–\(percent(wer.max))")
        }
        if let lineF1 = summary.lineBreakF1 { parts.append(String(format: "line F1 %.2f", lineF1.median)) }
        if let rtf = summary.realTimeFactor { parts.append(String(format: "RTF %.3f", rtf.median)) }
        if let text = summary.textSecondsPerMinute { parts.append(String(format: "M text %.1f s/min", text.median)) }
        if let fixable = summary.fixableShare { parts.append("fixable \(percent(fixable))") }
        return parts.joined(separator: "\n")
    }

    static func percent(_ value: Double) -> String { String(format: "%.1f %%", value * 100) }
}
#endif
