import AnamnesisKit
import Speech
import SwiftUI

/// The speech model, storage, privacy, *Delete all data* and version (spec 013, PRD M8, M9).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var usage: AppEnvironment.StorageUsage?
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let assets = environment.transcripts?.assets { modelSection(assets) }
                storageSection
                privacySection
                deleteSection
                aboutSection
                #if DEBUG
                Section {
                    NavigationLink("Files in Application Support") { AppDataFilesView() }
                } footer: {
                    Text("DEBUG: lists every file, for checking Delete all data (spec 013 AC1).")
                }
                #endif
            }
            .navigationTitle("Settings")
            .task(id: environment.dataDeletedAt) { usage = await environment.storageUsage() }
            .refreshable { usage = await environment.storageUsage() }
        }
    }

    // MARK: - Speech model (R1)

    private func modelSection(_ assets: AssetManager) -> some View {
        Section {
            LabeledContent("English", value: modelStatus(assets.state))
            if case .installing(let fraction) = assets.state {
                ProgressView(value: fraction)
            }
            if needsDownload(assets.state) {
                Button("Download speech model", systemImage: "arrow.down.circle") {
                    Task { await assets.install(locale: TranscriptionQueue.locale, config: TranscriptionQueue.config) }
                }
            }
        } header: {
            Text("Speech model")
        } footer: {
            Text("Apple downloads the English speech model once, through the system. Your audio and your poems "
                 + "never leave this device.")
        }
        .task { await assets.refresh(locale: TranscriptionQueue.locale, config: TranscriptionQueue.config) }
    }

    private func modelStatus(_ state: AssetState) -> String {
        switch state {
        case .status(.installed): "Installed"
        case .status(.supported): "Not downloaded"
        default: state.label
        }
    }

    private func needsDownload(_ state: AssetState) -> Bool {
        switch state {
        case .status(let status): status != .installed && status != .unsupported
        case .failed: true
        default: false
        }
    }

    // MARK: - Storage (R2)

    private var storageSection: some View {
        Section {
            LabeledContent("Captures", value: Self.bytes(usage?.captures))
            LabeledContent("Library", value: Self.bytes(usage?.library))
            LabeledContent("Diagnostics", value: Self.bytes(usage?.diagnostics))
        } header: {
            Text("Storage")
        } footer: {
            Text("Captures holds audio until it is transcribed, then only the text. Diagnostics is the app's own log.")
        }
    }

    private static func bytes(_ value: Int64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "–"
    }

    // MARK: - Privacy (R4)

    private var privacySection: some View {
        Section("Privacy") {
            Label("Anamnesis records only the sound other apps play while you capture. It never uses your "
                  + "microphone.", systemImage: "speaker.wave.2")
            Label("Transcription happens on this device. Nothing is sent anywhere: no account, no analytics, "
                  + "no cloud.", systemImage: "iphone")
            Label("Audio is deleted once it is transcribed; only the text is kept.", systemImage: "trash")
            Label("Your library is included in your device backup; capture audio is not.",
                  systemImage: "externaldrive")
        }
        .font(.callout)
    }

    // MARK: - Delete all (R3)

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Label("Delete all data", systemImage: "trash")
                }
            }
            .disabled(isDeleting || environment.capture.isCapturing)
            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            }
        } footer: {
            Text(environment.capture.isCapturing
                 ? "Stop the capture to delete data."
                 : "Removes every capture, Moment and poem, and the app's log. This cannot be undone.")
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAll() }
        } message: {
            Text("Every capture, Moment and poem is removed from this device. This cannot be undone.")
        }
    }

    private func deleteAll() {
        isDeleting = true
        Task {
            do {
                try await environment.deleteAllData()
                errorText = nil
            } catch {
                errorText = "Could not delete everything: \(error.localizedDescription)"
            }
            isDeleting = false
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Section("About") {
            LabeledContent("Version", value: "\(version) (\(build))")
        }
    }
}

#if DEBUG
/// Every file under Application Support with its size (spec 013 AC1 evidence).
private struct AppDataFilesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [AppDataFiles.Entry] = []

    var body: some View {
        List {
            if entries.isEmpty { Text("No files.").foregroundStyle(.secondary) }
            ForEach(entries, id: \.path) { entry in
                LabeledContent(entry.path,
                               value: ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file))
                    .font(.caption.monospaced())
            }
        }
        .navigationTitle("Application Support")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let support = environment.supportDirectory else { return }
        entries = await Task.detached { AppDataFiles.files(under: support) }.value
    }
}
#endif
