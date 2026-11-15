import AnamnesisKit
import SwiftData
import SwiftUI

/// The home screen (spec 015 R2): the capture orb, then captures still on their way, then recent ones. Since
/// spec 016 R1 a capture's poems go straight to the library, so a finished capture links there instead of to a
/// review screen.
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

    var body: some View {
        NavigationStack {
            List {
                CaptureHero().cardRow()
                errors
                ControlSetupCard().cardRow()
                sessions
            }
            .listStyle(.plain)
            // The setup card's row is often empty; without this it would keep a 44-pt gap.
            .environment(\.defaultMinListRowHeight, 0)
            .paperBackground()
            .navigationTitle("Listen")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await environment.refreshSessions() }
            .animation(.smooth, value: stored.map(\.spoolSessionID))
            .confirmationDialog("Delete this capture?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete capture", role: .destructive) { deletePending() }
            } message: {
                Text("The capture is removed. Its poems stay in your library.")
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
                        Text("No metrics for this capture.").padding()
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

    /// One pass: each session's status is computed once, from one manifest lookup, and split into the two groups.
    @ViewBuilder
    private var sessions: some View {
        let manifests = CaptureSessionStatus.manifests(in: environment)
        let rows = stored.map { session in
            (session: session, status: CaptureSessionStatus(session: session, environment: environment,
                                                             manifest: manifests[session.spoolSessionID]))
        }
        let attention = rows.filter { $0.status.needsAttention($0.session) }
        let earlier = rows.filter { !$0.status.needsAttention($0.session) }
        if stored.isEmpty {
            EmptyCapturesCard().cardRow()
        }
        if !attention.isEmpty {
            Eyebrow("In progress").padding(.top, 14).cardRow()
            ForEach(attention, id: \.session.id) { row($0.session, status: $0.status) }
        }
        if !earlier.isEmpty {
            Eyebrow("Recent").padding(.top, 14).cardRow()
            ForEach(earlier, id: \.session.id) { row($0.session, status: $0.status) }
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
            Button("Delete capture", systemImage: "trash", role: .destructive) { pendingDelete = session }
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

    /// A session link (Live Activity) lands here, where the capture's card shows its progress.
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

/// First run, nothing captured yet: the three steps, once more, where the list will be.
private struct EmptyCapturesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("How it works")
            StepRow(number: 1, text: "Tap the orb and choose **Share Entire Screen**.")
            StepRow(number: 2, text: "Open TikTok or Instagram and play the poem.")
            StepRow(number: 3, text: "Come back and stop. Each poem you heard lands in your **Library**.")
        }
        .card()
        .padding(.top, 8)
    }
}

struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(Theme.ember)
                .frame(width: 26, height: 26)
                .background(Theme.ember.opacity(0.12), in: .circle)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
        }
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
