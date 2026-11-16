import AnamnesisKit
import SwiftData
import SwiftUI

/// The home screen, the **Transcribe** tab (spec 015 R2; spec 019 R5; spec 020): the orb with its step track, the
/// speech model's progress while a new user's download runs, the tips, recordings still on their way (or failed,
/// with their fix), and one quiet card into the Library. Finished recordings are not listed: their transcripts are
/// already in the Library. The type keeps its old name; the tab was *Listen* until spec 020.
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
    /// Recordings not yet transcribed, newest first (spec 009: the store is the list's source). Transcribed ones are
    /// never listed, so they are not fetched: a status per session ever recorded was rebuilt on each progress tick.
    @Query private var unfinished: [CaptureSession]
    @Query private var transcripts: [Poem]

    init(showLibrary: @escaping () -> Void = {}) {
        self.showLibrary = showLibrary
        let transcribed = StoredSessionState.transcribed.rawValue
        _unfinished = Query(filter: #Predicate<CaptureSession> { $0.stateRaw != transcribed },
                            sort: \.startedAt, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            List {
                CaptureHero().cardRow()
                SpeechModelBanner().cardRow()
                errors
                ControlSetupCard().cardRow()
                inProgress
                libraryRow
            }
            .listStyle(.plain)
            // The setup card's row is often empty; without this it would keep a 44-pt gap.
            .environment(\.defaultMinListRowHeight, 0)
            .paperBackground()
            .navigationTitle("Transcribe")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await environment.refreshSessions() }
            .animation(.smooth, value: unfinished.map(\.spoolSessionID))
            .confirmationDialog("Delete this recording?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete recording", role: .destructive) { deletePending() }
            } message: {
                Text("The recording is removed. Any transcripts from it stay in your library.")
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
        let manifests = unfinished.isEmpty ? [:] : CaptureSessionStatus.manifests(in: environment)
        let rows = unfinished.compactMap { session -> (session: CaptureSession, status: CaptureSessionStatus)? in
            let status = CaptureSessionStatus(session: session, environment: environment,
                                              manifest: manifests[session.spoolSessionID])
            return status.needsAttention ? (session, status) : nil
        }
        if !rows.isEmpty {
            Eyebrow("In progress").padding(.top, 14).cardRow()
            ForEach(rows, id: \.session.id) { row($0.session, status: $0.status) }
        }
    }

    /// One way into the Library, once there is something in it.
    @ViewBuilder
    private var libraryRow: some View {
        if !transcripts.isEmpty {
            Button(action: showLibrary) { LibraryCard(count: transcripts.count) }
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

/// The Library, minimal (spec 020 R5): the count set large in New York, one quiet line under it, an arrow. Nothing
/// about the last recording; the Library itself tells that story.
private struct LibraryCard: View {
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count, format: .number)
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.smooth, value: count)
                Text(count == 1 ? "transcript in your Library" : "transcripts in your Library")
                    .font(Theme.verse(.callout))
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ember)
                .frame(width: 44, height: 44)
                .background(Theme.ember.opacity(0.12), in: .circle)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Spec 020 R7: while a new user's speech model downloads (or is waiting for a connection), one line says so, with
/// progress. Recordings made meanwhile wait and transcribe themselves once it lands. Hidden once installed.
private struct SpeechModelBanner: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let queue = environment.transcripts, queue.isWaitingForModel {
            let state = queue.assets.state
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: state.isFailed ? "wifi.exclamationmark" : "arrow.down.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ember)
                    .symbolEffect(.pulse, options: .repeating, isActive: !state.isFailed)
                    .frame(width: 40, height: 40)
                    .background(Theme.ember.opacity(0.12), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.isFailed ? "Speech recognition is waiting for internet"
                                         : "Getting speech recognition ready")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if case .installing(let fraction) = state {
                        ProgressView(value: fraction).tint(Theme.ember)
                    } else {
                        Text(state.isFailed
                             ? "A one-time download from Apple. It continues on its own once you’re online."
                             : "A one-time download from Apple. You can record now; it transcribes when ready.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                if state.isFailed {
                    Button("Retry") { Task { await queue.prepareModel() } }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .card(padding: 14)
            .accessibilityElement(children: .combine)
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
