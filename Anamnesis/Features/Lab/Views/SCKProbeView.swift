#if DEBUG && canImport(ScreenCaptureKit)
import AnamnesisKit
import SwiftUI

// SPIKE: Lab → SCK Probe. Operator UI for DEVICE_TEST_PROTOCOLS §3.
struct SCKProbeView: View {
    @Bindable var model: SCKProbeViewModel

    var body: some View {
        List {
            statusSection
            SCKProbeSettingsSection(settings: $model.settings)
                .disabled(model.isCapturing)
            controlSection
            if let live = model.live, model.isCapturing {
                SCKLiveSection(report: live, level: model.liveLevel)
                markerSection
            }
            if let run = model.lastRun { RunSection(title: "Last run", run: run) }
            PreviousRunsSection(runs: model.runs)
            logSection
        }
        .navigationTitle("SCK Probe")
        .task { await model.pollLive() }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Picker available", value: model.isPickerAvailable ? "yes" : "no")
            LabeledContent("State", value: model.isCapturing ? "capturing" : "idle")
            if let error = model.lastError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }

    private var controlSection: some View {
        Section {
            if model.isCapturing {
                Button("Stop capture", systemImage: "stop.circle.fill", role: .destructive) {
                    Task { await model.stop() }
                }
            } else {
                Button("Start capture", systemImage: "record.circle") { model.start() }
                    .disabled(!model.isPickerAvailable)
            }
        }
    }

    private var markerSection: some View {
        Section("Markers") {
            HStack {
                Button("Audible start") { model.mark(.audibleStart) }
                Spacer()
                Button("Audible end") { model.mark(.audibleEnd) }
            }
            .buttonStyle(.bordered)
            HStack {
                TextField("Note (e.g. switched to Instagram)", text: $model.noteText)
                Button("Add") { model.mark(.note) }
                    .disabled(model.noteText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var logSection: some View {
        Section("Log & events") {
            Button("Copy log", systemImage: "doc.on.doc") { model.copyLog() }
            if let url = model.exportLogURL() {
                ShareLink(item: url) { Label("Export log", systemImage: "square.and.arrow.up") }
            }
            ForEach(model.eventLines, id: \.self) { line in
                Text(line).font(.caption.monospaced())
            }
        }
    }
}

private struct SCKProbeSettingsSection: View {
    @Binding var settings: SCKCaptureBackend.Settings

    var body: some View {
        Section("Run setup") {
            TextField("Run label (e.g. R-002 S1 C1 T2)", text: $settings.runLabel)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Picker("Picker style", selection: $settings.style) {
                ForEach(SCKPickerCoordinator.Style.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Sample rate", selection: $settings.sampleRate) {
                Text("SCK default").tag(0)
                Text("16 kHz").tag(16_000)
                Text("48 kHz").tag(48_000)
            }
            Picker("Channels", selection: $settings.channelCount) {
                Text("SCK default").tag(0)
                Text("Mono").tag(1)
                Text("Stereo").tag(2)
            }
            Toggle("Add .screen output", isOn: $settings.addScreenOutput)
            Toggle("Save first 20 s of sound (raw.caf)", isOn: $settings.rawDump)
        }
    }
}

private struct SCKLiveSection: View {
    let report: ProbeReport
    let level: ProbeReport.TimelineSecond?

    var body: some View {
        let counters = report.counters
        Section("Live") {
            LabeledContent("Sharing", value: "\(report.config.filterStyle ?? "?") · "
                           + "\(report.config.filterContentRect ?? "?")")
            LabeledContent("Elapsed", value: Duration.seconds(report.durationSec)
                .formatted(.time(pattern: .minuteSecond)))
            LabeledContent("Level (this second)", value: level
                .map { String(format: "%.1f dBFS", $0.rmsDb) } ?? "no audio")
            LabeledContent("Audio received", value: String(format: "%.1f s", counters.audioSecondsTotal))
            LabeledContent("Buffers", value: counters.byType.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }.joined(separator: " · "))
            LabeledContent("Silent buffers", value: String(format: "%.0f %%", counters.silentRatio * 100))
            LabeledContent("PTS gaps", value: "\(counters.ptsGaps.count) (max \(Int(counters.ptsGaps.maxMs)) ms)")
            LabeledContent("Format changes · drops", value: "\(counters.formatChanges) · \(counters.dropsQueueFull)")
            LabeledContent("Errors", value: "\(counters.errors.count)")
            if let format = report.firstBuffer?.format {
                LabeledContent("Format", value: "\(Int(format.sampleRate)) Hz · \(format.channels) ch · "
                               + "\(format.sampleFormat.rawValue)\(format.isInterleaved ? "" : " planar")")
            }
        }
    }
}

private struct RunSection: View {
    let title: String
    let run: ProbeRun

    var body: some View {
        Section(title) {
            RunSummary(run: run)
            ShareLink(item: run.reportURL) { Label("Export report", systemImage: "square.and.arrow.up") }
            if let raw = run.rawDumpURL {
                ShareLink(item: raw) { Label("Export raw.caf", systemImage: "waveform") }
            }
        }
    }
}

private struct PreviousRunsSection: View {
    let runs: [ProbeRun]

    var body: some View {
        Section("Saved runs (\(runs.count))") {
            ForEach(runs) { run in
                ShareLink(item: run.reportURL) { RunSummary(run: run) }
            }
        }
    }
}

private struct RunSummary: View {
    let run: ProbeRun

    var body: some View {
        let report = run.report
        VStack(alignment: .leading, spacing: 2) {
            Text(report.runLabel.isEmpty ? "unlabeled" : report.runLabel).font(.headline)
            Text("\(report.startedAt.formatted(date: .abbreviated, time: .shortened)) · "
                 + "\(Int(report.durationSec)) s · audio \(Int(report.counters.audioSecondsTotal)) s · "
                 + "silent \(Int(report.counters.silentRatio * 100)) %")
                .font(.caption)
            Text("stop: \(report.stop.map { $0.reason.rawValue } ?? "not finished (app killed?)")")
                .font(.caption)
                .foregroundStyle(report.stop == nil ? .orange : .secondary)
        }
    }
}
#endif
