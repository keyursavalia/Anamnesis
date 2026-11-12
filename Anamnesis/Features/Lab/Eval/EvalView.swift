#if DEBUG
import AnamnesisKit
import SwiftUI
import UniformTypeIdentifiers

// SPIKE: Lab → Test B (spec 004): corpus import, sweep choice, runs.
struct EvalView: View {
    @Bindable var model: EvalViewModel
    @State private var isImporting = false

    var body: some View {
        List {
            corpusSection
            newRunSection
            Section("Runs (\(model.runs.count))") {
                ForEach(model.runs) { run in
                    NavigationLink {
                        EvalRunView(model: model, runID: run.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.id).font(.headline.monospacedDigit())
                            Text("\(run.sweep) · \(run.results.count)/\(run.totalJobs) jobs"
                                 + (run.id == model.activeRunID ? " · running" : ""))
                                .font(.caption)
                        }
                    }
                }
                .onDelete { offsets in offsets.map { model.runs[$0] }.forEach(model.delete) }
            }
        }
        .navigationTitle("Test B")
        .task { await model.load() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            Task { await model.corpus.importFolder(result) }
        }
    }

    private var corpusSection: some View {
        Section {
            LabeledContent("Clips", value: "\(model.corpus.clips.count)")
            if !model.corpus.clips.isEmpty {
                LabeledContent("By category", value: model.corpus.clipsByCategory
                    .map { "\($0.category) \($0.count)" }.joined(separator: " · "))
            }
            ForEach(Array(model.corpus.issues.enumerated()), id: \.offset) { _, issue in
                Text("\(issue.file): \(issue.problem.rawValue)").font(.caption).foregroundStyle(.orange)
            }
            if let error = model.corpus.lastError { Text(error).foregroundStyle(.red) }
            Button("Import corpus folder…", systemImage: "folder.badge.plus") { isImporting = true }
                .disabled(model.isRunning)
        } header: {
            Text("Corpus")
        } footer: {
            Text("Pick a folder with clips/ (m4a, wav, caf, mp4, mov), truth/<clip>.txt and an optional meta.csv "
                 + "(clip,category,language,notes). It replaces the current corpus and stays on this device.")
        }
    }

    private var newRunSection: some View {
        Section {
            Picker("Sweep", selection: $model.sweep) {
                ForEach(ExperimentSweep.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text(model.sweep.configs.map(\.name).joined(separator: ", ")).font(.caption)
            Button("Start run", systemImage: "play.circle") { model.startRun() }
                .disabled(model.isRunning || model.corpus.clips.isEmpty)
            if let progress = model.progress {
                ProgressView(value: Double(progress.index - 1), total: Double(progress.total)) {
                    Text("Job \(progress.index)/\(progress.total): \(progress.clipID) · \(progress.configName)")
                        .font(.caption)
                }
                Button("Pause", systemImage: "pause.circle", role: .destructive) { model.cancel() }
            }
            if let error = model.lastError { Text(error).foregroundStyle(.red) }
        } header: {
            Text("New run")
        } footer: {
            Text("Jobs run one at a time and are saved after each one. Pause, then Resume on the run, to continue; "
                 + "the job in progress restarts.")
        }
    }
}
#endif
