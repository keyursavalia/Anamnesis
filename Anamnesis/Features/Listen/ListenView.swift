import AnamnesisKit
import SwiftData
import SwiftUI

/// The home screen (spec 015 R2, reworked): the orb with its step track, the Control Center invite, recordings still
/// on their way (or failed, with their fix), and one row into the Library that says what the last one brought.
/// Finished recordings are not listed: since spec 016 R1 their poems are already in the Library.
struct ListenView: View {
    /// Switches to the Library tab.
    var showLibrary: () -> Void = {}
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var deleteError: String?
    @State private var pendingDelete: CaptureSession?
    #if DEBUG
    @State private var metricsSession: CaptureSession?
    #endif
    /// Newest first (spec 009: the store is the list's source).
    @Query(sort: \CaptureSession.startedAt, order: .reverse) private var stored: [CaptureSession]
    @Query private var poems: [Poem]

    var body: some View {
        NavigationStack {
            List {
                CaptureHero().cardRow()
                errors
                ControlSetupCard().cardRow()
                inProgress
                libraryRow
            }
            .listStyle(.plain)
            // The setup card's row is often empty; without this it would keep a 44-pt gap.
            .environment(\.defaultMinListRowHeight, 0)
            .paperBackground()
            .navigationTitle("Listen")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await environment.refreshSessions() }
            .animation(.smooth, value: stored.map(\.spoolSessionID))
            .confirmationDialog("Delete this recording?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete recording", role: .destructive) { deletePending() }
            } message: {
                Text("The recording is removed. Any poems from it stay in your library.")
            }
            #if DEBUG
            .sheet(item: $metricsSession) { session in
                ScrollView {
                    if let metrics = session.metrics {
                        SessionMetricsCard(metrics: metrics, session: session,
                                           summary: environment.sessions?.sessions.first {
                                               $0.id == session.spoolSessionID
                                           })
                        .padding()
                    } else {
                        Text("No metrics for this recording.").padding()
                    }
                }
                .paperBackground()
                .presentationDetents([.medium, .large])
            }
            #endif
        }
        .onChange(of: environment.openSessionID, initial: true) { openRequestedSession() }
        #if !DEBUG
        // DEBUG keeps rung 2 in Lab → Capture (spec 005 timings); only one screen may present the picker.
        .onChange(of: AutoPresentTrigger(id: environment.launchRequest?.id, phase: scenePhase), initial: true) {
            autoPresentIfPending()
        }
        #endif
    }

    // MARK: - Rows

    @ViewBuilder
    private var errors: some View {
        ForEach([environment.capture.lastError, environment.library.loadError, deleteError].compactMap(\.self),
                id: \.self) { ErrorLine($0).cardRow() }
    }

    /// Recordings still on their way, or failed. Each status is computed once, from one manifest lookup.
    @ViewBuilder
    private var inProgress: some View {
        let manifests = CaptureSessionStatus.manifests(in: environment)
        let rows = stored.compactMap { session -> (session: CaptureSession, status: CaptureSessionStatus)? in
            let status = CaptureSessionStatus(session: session, environment: environment,
                                              manifest: manifests[session.spoolSessionID])
            return status.needsAttention(session) ? (session, status) : nil
        }
        if !rows.isEmpty {
            Eyebrow("In progress").padding(.top, 14).cardRow()
            ForEach(rows, id: \.session.id) { row($0.session, status: $0.status) }
        }
    }

    /// One way into the Library, once there is something to find there.
    @ViewBuilder
    private var libraryRow: some View {
        if !poems.isEmpty || stored.contains(where: { $0.state == .transcribed }) {
            Button(action: showLibrary) {
                LibrarySummaryCard(poemCount: poems.count, latest: stored.first { $0.state == .transcribed })
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityHint("Opens your Library")
            .padding(.top, 14)
            .cardRow()
        }
    }

    private func row(_ session: CaptureSession, status: CaptureSessionStatus) -> some View {
        let card = SessionCard(session: session, status: status)
        return Group {
            if card.opensLibrary {
                Button(action: showLibrary) { card }
                    .buttonStyle(CardButtonStyle())
                    .accessibilityHint("Opens your Library")
            } else {
                card
            }
        }
        .cardRow()
        .swipeActions {
            Button("Delete", systemImage: "trash") { pendingDelete = session }.tint(Theme.danger)
        }
        .contextMenu {
            #if DEBUG
            Button("Metrics (DEBUG)", systemImage: "chart.bar") { metricsSession = session }
            #endif
            Button("Delete recording", systemImage: "trash", role: .destructive) { pendingDelete = session }
        }
    }

    // MARK: - Actions

    private func deletePending() {
        guard let id = pendingDelete?.spoolSessionID else { return }
        pendingDelete = nil
        deleteError = nil
        Task {
            do {
                try await environment.transcripts?.delete(sessionID: id)
            } catch {
                deleteError = "Could not delete: \(error.localizedDescription)"
            }
        }
    }

    /// A session link (Live Activity) lands here, where the recording's card shows its progress.
    private func openRequestedSession() {
        guard environment.openSessionID != nil else { return }
        environment.openSessionID = nil
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

/// The Library's count, and what the most recent finished recording brought: the answer to "did it work?".
private struct LibrarySummaryCard: View {
    let poemCount: Int
    let latest: CaptureSession?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.sage)
                .frame(width: 44, height: 44)
                .background(Theme.sage.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(poemCount == 1 ? "1 poem in your Library" : "\(poemCount) poems in your Library")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if let outcome {
                    Text(outcome).font(.footnote).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary.opacity(0.6))
        }
        .card(padding: 16)
        .contentShape(.rect(cornerRadius: Theme.cornerRadius))
    }

    private var outcome: String? {
        guard let latest else { return nil }
        let when = CaptureFormat.when(latest.startedAt)
        let kept = latest.keptPoemCount
        if latest.moments.isEmpty { return String(localized: "No speech in your last recording · \(when)") }
        if kept == 0 { return String(localized: "Your last recording had no poems · \(when)") }
        return kept == 1 ? String(localized: "1 new from your last recording · \(when)")
                         : String(localized: "\(kept) new from your last recording · \(when)")
    }
}

private struct AutoPresentTrigger: Equatable {
    let id: UUID?
    let phase: ScenePhase
}

#Preview {
    let environment = AppEnvironment()
    ListenView()
        .environment(environment)
        .modelContainer(environment.library.container)
}
