import AnamnesisKit
import SwiftData
import SwiftUI

/// The product home (spec 008 R2): start or stop a capture, and the list of capture sessions.
struct CapturesView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [String] = []
    @State private var deleteError: String?
    /// Newest first (spec 009: the store is the list's source).
    @Query(sort: \CaptureSession.startedAt, order: .reverse) private var stored: [CaptureSession]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                captureSection
                sessionsSection
            }
            .navigationTitle("Captures")
            .navigationDestination(for: String.self) { CaptureSessionDetailView(sessionID: $0) }
            .refreshable { await environment.refreshSessions() }
        }
        .onChange(of: environment.openSessionID, initial: true) { openRequestedSession() }
        #if !DEBUG
        // DEBUG keeps rung 2 in Lab → Capture (spec 005 timings); only one screen may present the picker.
        .onChange(of: AutoPresentTrigger(id: environment.launchRequest?.id, phase: scenePhase), initial: true) {
            autoPresentIfPending()
        }
        #endif
    }

    // MARK: - Capture

    private var captureSection: some View {
        let capture = environment.capture
        return Section {
            if capture.isCapturing {
                Button("Stop capture", systemImage: "stop.circle.fill", role: .destructive) {
                    Task { await capture.stop() }
                }
                .font(.title3.weight(.semibold))
            } else {
                Button("Capture", systemImage: "record.circle") { try? capture.start(label: "captures") }
                    .font(.title3.weight(.semibold))
                    .disabled(!capture.isPickerAvailable)
            }
            if capture.isCapturing {
                Label("Capturing. The session appears below when you stop.", systemImage: "record.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = capture.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if let error = environment.library.loadError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("""
                    Tap Capture, then choose Share Entire Screen in the system sheet and go back to your reel. \
                    Anamnesis keeps only the sound other apps play, never your microphone, and transcribes it on \
                    this device. A red indicator shows while capturing; tap it to stop. The Capture poem control \
                    in Control Center does the same in one tap.
                    """)
                if !capture.isPickerAvailable {
                    Text("Capture needs a device with screen sharing; it is not available here.")
                }
            }
        }
    }

    // MARK: - Sessions

    @ViewBuilder
    private var sessionsSection: some View {
        let sessions = stored
        Section {
            if sessions.isEmpty {
                Text("No captures yet.").foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                NavigationLink(value: session.spoolSessionID) {
                    CaptureSessionRow(session: session)
                }
            }
            .onDelete { delete(sessions, at: $0) }
            if let deleteError {
                Text(deleteError).font(.callout).foregroundStyle(.red)
            }
        } header: {
            Text("Sessions")
        }
    }

    private func delete(_ sessions: [CaptureSession], at offsets: IndexSet) {
        deleteError = nil
        let ids = offsets.map { sessions[$0].spoolSessionID }
        Task {
            for id in ids {
                do {
                    try await environment.transcripts?.delete(sessionID: id)
                } catch {
                    deleteError = "Could not delete: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Launch requests

    private func openRequestedSession() {
        guard let id = environment.openSessionID else { return }
        environment.openSessionID = nil
        path = [id]
    }

    /// Rung 2 (`Open capture`): present once per request, only when the scene is active.
    private func autoPresentIfPending() {
        guard scenePhase == .active, environment.launchRequest?.autoPresentPending == true else { return }
        environment.launchRequest?.autoPresentPending = false
        guard !environment.capture.isCapturing else { return }
        environment.launchRequest?.startRequestedAt = Date()
        try? environment.capture.start(label: "launch-rung\(environment.launchRequest?.rung ?? 0)")
    }
}

private struct AutoPresentTrigger: Equatable {
    let id: UUID?
    let phase: ScenePhase
}

#Preview {
    let environment = AppEnvironment()
    CapturesView()
        .environment(environment)
        .modelContainer(environment.library.container)
}
