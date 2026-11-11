#if DEBUG
import AnamnesisKit
import SwiftUI

// SPIKE: Lab → Spool sessions (spec 002 R10): list, detail, listen-back, export, delete.
struct SpoolSessionsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            if let sessions = environment.sessions {
                if !sessions.lastRecovery.isEmpty {
                    Section("Recovered at last scan") {
                        ForEach(sessions.lastRecovery, id: \.sessionID) { result in
                            Text("\(result.sessionID): \(result.state.rawValue), "
                                 + String(format: "%.1f s", Double(result.frames) / SpoolFormat.standard.sampleRate)
                                 + (result.discardedFiles.isEmpty ? "" : ", discarded \(result.discardedFiles)"))
                                .font(.caption)
                        }
                    }
                }
                Section("Sessions (\(sessions.sessions.count))") {
                    ForEach(sessions.sessions) { summary in
                        NavigationLink(value: summary.id) { SpoolSessionRow(summary: summary) }
                    }
                }
            } else {
                Text("Application Support is unavailable; nothing is spooled.").foregroundStyle(.red)
            }
        }
        .navigationTitle("Spool sessions")
        .navigationDestination(for: String.self) { id in
            if let summary = environment.sessions?.sessions.first(where: { $0.id == id }) {
                SpoolSessionDetailView(summary: summary)
            }
        }
        .refreshable { await environment.refreshSessions() }
        .task { await environment.refreshSessions() }
    }
}

private struct SpoolSessionRow: View {
    let summary: SpoolSessionSummary

    var body: some View {
        let manifest = summary.manifest
        VStack(alignment: .leading, spacing: 2) {
            Text(manifest?.label ?? summary.id).font(.headline)
            Text([
                manifest.map { $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "no manifest",
                manifest.map { Duration.seconds($0.durationSec).formatted(.time(pattern: .minuteSecond)) } ?? "–",
                summary.sizeBytes.formatted(.byteCount(style: .file))
            ].joined(separator: " · "))
            .font(.caption)
            Text(manifest?.state.rawValue ?? "unknown")
                .font(.caption)
                .foregroundStyle(manifest?.state == .finished ? Color.secondary : Color.orange)
        }
    }
}

private struct SpoolSessionDetailView: View {
    let summary: SpoolSessionSummary
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var player = SegmentPlayer()
    @State private var deleteError: String?
    @State private var showsTranscription = false

    var body: some View {
        List {
            if let manifest = summary.manifest {
                SpoolManifestSection(manifest: manifest, sizeBytes: summary.sizeBytes, isDone: summary.isDone)
                segmentSection(manifest)
            } else {
                Text("No readable manifest.").foregroundStyle(.orange)
            }
            Section {
                Button("Transcribe", systemImage: "text.bubble") {
                    player.stop()
                    environment.transcriptionLab().transcribe(session: summary.session)
                    showsTranscription = true
                }
                .disabled(environment.isCapturing || summary.manifest == nil)
                .accessibilityHint("Transcribes this session on device as one timeline")
                ShareLink(items: exportURLs) { Label("Export manifest + segments", systemImage: "square.and.arrow.up") }
                Button("Delete session", systemImage: "trash", role: .destructive, action: delete)
                    .disabled(environment.isCapturing)
                if let deleteError { Text(deleteError).foregroundStyle(.red) }
            }
        }
        .navigationTitle(summary.manifest?.label ?? summary.id)
        .navigationDestination(isPresented: $showsTranscription) {
            TranscriptionLabView(model: environment.transcriptionLab())
        }
        .onDisappear { player.stop() }
    }

    private func segmentSection(_ manifest: SpoolManifest) -> some View {
        Section {
            ForEach(manifest.segments, id: \.index) { segment in
                let url = summary.session.directory.appending(path: segment.fileName)
                Button {
                    player.toggle(url)
                } label: {
                    LabeledContent(segment.fileName, value: String(
                        format: "@%.0f s · %.1f s", segment.startOffsetSec,
                        manifest.format.seconds(forFrames: segment.frames))
                        + (segment.closedCleanly ? "" : " · not closed"))
                }
                .disabled(environment.isCapturing)
                .accessibilityLabel(player.playingURL == url ? "Stop \(segment.fileName)" : "Play \(segment.fileName)")
            }
            if let error = player.lastError { Text(error).foregroundStyle(.red) }
        } header: {
            Text("Segments")
        } footer: {
            Text(environment.isCapturing ? "Playback is disabled while capturing." : "Tap a segment to play or stop.")
        }
    }

    private var exportURLs: [URL] {
        [summary.session.manifestURL] + summary.session.segmentFiles().map(\.url)
    }

    private func delete() {
        player.stop()
        do {
            try environment.sessions?.delete(summary)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct SpoolManifestSection: View {
    let manifest: SpoolManifest
    let sizeBytes: Int
    let isDone: Bool

    var body: some View {
        let counters = manifest.counters
        Section("Manifest") {
            LabeledContent("State", value: manifest.state.rawValue + (isDone ? " · DONE" : " · no DONE"))
            LabeledContent("Created", value: manifest.createdAt.formatted(date: .abbreviated, time: .standard))
            if let finished = manifest.finishedAt {
                LabeledContent("Finished", value: finished.formatted(date: .omitted, time: .standard))
            }
            LabeledContent("Duration", value: String(format: "%.2f s", manifest.durationSec))
            LabeledContent("Size", value: sizeBytes.formatted(.byteCount(style: .file)))
            LabeledContent("Format", value: "\(Int(manifest.format.sampleRate)) Hz · \(manifest.format.channels) ch "
                           + "· Int16 · \(manifest.format.segmentSeconds) s segments")
            LabeledContent("Drops (buffers · frames)", value: "\(counters.dropsQueueFull) · \(counters.droppedFrames)")
            LabeledContent("Clipped samples", value: "\(counters.clippedSamples)")
            LabeledContent("Format changes · invalid", value: "\(counters.formatChanges) · \(counters.invalidBuffers)")
            LabeledContent("PTS gaps", value: "\(counters.ptsGaps.count) (max \(Int(counters.ptsGaps.maxMs)) ms)")
            LabeledContent("Write errors", value: "\(counters.writeErrors)")
            if let error = counters.firstError { Text(error).foregroundStyle(.red).font(.caption) }
        }
    }
}
#endif
