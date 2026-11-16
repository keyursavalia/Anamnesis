import AnamnesisKit
import Speech
import SwiftUI

/// App settings (spec 016 R12): the speech model (spec 013 R1), the library's size on disk, and *Delete all data*
/// (spec 013 R3) as a red button that asks first.
struct AppSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var librarySize: Int64?
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let assets = environment.transcripts?.assets { modelSection(assets) }
            storageSection
            deleteSection
            #if DEBUG
            Section {
                NavigationLink("Files in Application Support") { AppDataFilesView() }
            } footer: {
                Text("DEBUG: lists every file, for checking Delete all data (spec 013 AC1).")
            }
            .listRowBackground(Theme.surface)
            #endif
        }
        .paperBackground()
        .tint(Theme.ember)
        .navigationTitle("App settings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: environment.dataDeletedAt) { librarySize = await environment.librarySize() }
    }

    // MARK: - Speech model

    private func modelSection(_ assets: AssetManager) -> some View {
        Section {
            LabeledContent {
                Text(modelStatus(assets.state))
            } label: {
                Label("English", systemImage: assets.state == .status(.installed) ? "checkmark.circle.fill"
                                                                                  : "arrow.down.circle")
                    .foregroundStyle(assets.state == .status(.installed) ? Theme.sage : Theme.ink)
            }
            if case .installing(let fraction) = assets.state {
                ProgressView(value: fraction)
            }
            if needsDownload(assets.state) {
                Button("Download speech model", systemImage: "arrow.down.circle") {
                    // Through the queue, so recordings waiting for the model start once it lands (spec 020 R7).
                    Task { await environment.transcripts?.prepareModel() }
                }
            }
        } header: {
            Eyebrow("Speech model")
        } footer: {
            Text("""
                Apple downloads the English speech model once, through the system. Your audio and your \
                transcripts never leave this device.
                """)
        }
        .listRowBackground(Theme.surface)
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

    // MARK: - Storage

    private var storageSection: some View {
        Section {
            LabeledContent {
                Text(librarySize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "–")
                    .monospacedDigit()
            } label: {
                Label("Library", systemImage: "books.vertical")
            }
        } header: {
            Eyebrow("Storage")
        } footer: {
            Text("Your transcripts, as text. Recorded audio is deleted once it is transcribed.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Delete all

    private var deleteSection: some View {
        Section {
            Button {
                confirmingDelete = true
            } label: {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text("Delete all data")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                // A capsule like the app's other buttons; its round ends match the row's own corners, so the row
                // no longer clips it unevenly.
                .background(Theme.dangerFill.opacity(isDeleteDisabled ? 0.4 : 1), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(CardButtonStyle())
            .disabled(isDeleteDisabled)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            if let errorText { ErrorLine(errorText).listRowBackground(Color.clear) }
        } footer: {
            Text(environment.capture.isCapturing
                 ? "Stop transcribing to delete data."
                 : "Removes every transcript and recording, and the app’s log, from this device. "
                    + "This cannot be undone.")
                .padding(.top, 6)
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAll() }
        } message: {
            Text("Every transcript and recording is removed from this device. This cannot be undone.")
        }
    }

    private var isDeleteDisabled: Bool { isDeleting || environment.capture.isCapturing }

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
