#if DEBUG
import AnamnesisKit
import Speech
import SwiftUI
import UniformTypeIdentifiers

// SPIKE: Lab → Transcription (spec 003 R1, R11): model install, configuration, import, live job status.
struct TranscriptionLabView: View {
    @Bindable var model: TranscriptionLabViewModel
    @State private var isImporting = false

    var body: some View {
        List {
            modelSection
            configSection
            inputSection
            jobSection
        }
        .navigationTitle("Transcription")
        .task { await model.load() }
        .onChange(of: model.localeID) { Task { await model.refreshAssets() } }
        .onChange(of: model.module) { Task { await model.refreshAssets() } }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio, .movie]) { model.importFile($0) }
    }

    private var modelSection: some View {
        Section {
            Picker("Locale", selection: $model.localeID) {
                ForEach(model.assets.supportedLocales, id: \.identifier) { locale in
                    Text(locale.identifier + (model.assets.installedLocaleIDs.contains(locale.identifier) ? " ✓" : ""))
                        .tag(locale.identifier)
                }
            }
            LabeledContent("Model", value: model.assets.state.label)
            if case .installing(let fraction) = model.assets.state {
                ProgressView(value: fraction).accessibilityLabel("Model download progress")
            }
            Button("Install model", systemImage: "arrow.down.circle") { Task { await model.installAssets() } }
                .disabled(model.assets.state != .status(.supported))
            Button("Re-check status", systemImage: "arrow.clockwise") { Task { await model.refreshAssets() } }
        } header: {
            Text("Speech model")
        } footer: {
            Text("iOS downloads the speech model once, through a system service. That download is the only network "
                 + "use; transcription itself runs entirely on this device.")
        }
    }

    private var configSection: some View {
        Section("Configuration") {
            Picker("Module", selection: $model.module) {
                ForEach(TranscriptionLabViewModel.ModuleChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Speech detector", selection: $model.detector) {
                Text("Off").tag(TranscriptionConfig.Sensitivity?.none)
                ForEach(TranscriptionConfig.Sensitivity.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag(Optional($0))
                }
            }
            Picker("Audio file reader", selection: $model.audioReader) {
                ForEach(TranscriptionLabViewModel.AudioReader.allCases) { Text($0.rawValue).tag($0) }
            }
        }
        .disabled(model.isRunning)
    }

    private var inputSection: some View {
        Section {
            Button("Import audio or video…", systemImage: "square.and.arrow.down") { isImporting = true }
                .disabled(model.isRunning || !model.assets.state.isInstalled)
            if model.isRunning {
                Button("Cancel", systemImage: "xmark.circle", role: .destructive) { model.cancel() }
            }
        } header: {
            Text("Input")
        } footer: {
            Text("To transcribe a capture, open Spool sessions → a session → Transcribe. Video is always read with "
                 + "AssetInputSequenceProvider.")
        }
    }

    private var jobSection: some View {
        Section("Job") {
            switch model.job {
            case .idle: Text("No job yet").foregroundStyle(.secondary)
            case .running(let source): Label("Transcribing \(source)…", systemImage: "waveform")
            case .finished: Label("Finished", systemImage: "checkmark.circle")
            case .failed(let message): Text(message).foregroundStyle(.red)
            }
            if let audioSec = model.audioSec { LabeledContent("Audio", value: String(format: "%.1f s", audioSec)) }
            if let format = model.analyzerFormat { LabeledContent("Analyzer format", value: format) }
            LabeledContent("Segments so far", value: "\(model.liveSegments.count)")
            if model.detector != nil { LabeledContent("Detector results", value: "\(model.speechRegionCount)") }
            if let last = model.liveSegments.last { Text(last.text).font(.caption).lineLimit(3) }
            if let transcript = model.transcript {
                NavigationLink("Open transcript") { TranscriptResultView(model: model, transcript: transcript) }
            }
        }
    }
}
#endif
