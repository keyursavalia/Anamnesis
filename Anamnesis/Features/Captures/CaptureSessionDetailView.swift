import AnamnesisKit
import SwiftData
import SwiftUI

/// One session's Moments (spec 008 R5) with review progress (spec 010); each Moment is a `MomentRow`.
/// Reads the library store (spec 009).
struct CaptureSessionDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let sessionID: String
    @Query private var matches: [CaptureSession]
    /// Poems from this session, to list the ones split off from a Moment's poem (spec 011).
    @Query private var poems: [Poem]
    @State private var player = ExcerptPlayer()
    @State private var editing: Poem?

    init(sessionID: String) {
        self.sessionID = sessionID
        _matches = Query(filter: #Predicate<CaptureSession> { $0.spoolSessionID == sessionID })
        _poems = Query(filter: #Predicate<Poem> { $0.sourceSessionID == sessionID }, sort: \Poem.createdAt)
    }

    var body: some View {
        let session = matches.first
        let summary = environment.sessions?.sessions.first { $0.id == sessionID }
        List {
            if let session {
                statusSection(session)
                momentSections(session, summary: summary)
                splitOffSection
                #if DEBUG
                if let metrics = session.metrics { metricsSection(metrics, session: session, summary: summary) }
                #endif
            } else {
                Text("This capture no longer exists.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(session?.startedAt.formatted(date: .abbreviated, time: .shortened) ?? "Capture")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
        .sheet(item: $editing) { PoemEditorView(poem: $0) }
    }

    // MARK: - Status

    @ViewBuilder
    private func statusSection(_ session: CaptureSession) -> some View {
        let status = CaptureSessionStatus(session: session, environment: environment)
        let job = environment.transcripts?.state(of: sessionID)
        if status.state != .transcribed {
            Section {
                Label(status.label, systemImage: status.systemImage)
                if case .running(let processed, let audio) = job, let audio, audio > 0 {
                    ProgressView(value: min(processed, audio), total: audio)
                }
                if let failure = status.failureText {
                    Text(failure).font(.callout).foregroundStyle(.red)
                    if case .modelNotInstalled = status.error {
                        Button("Download speech model", systemImage: "arrow.down.circle") {
                            Task { await environment.transcripts?.installModelAndRetry(sessionID) }
                        }
                        Text("Apple downloads the English speech model once; your audio never leaves this device.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !session.audioDeleted {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            Task { await environment.transcripts?.retry(sessionID) }
                        }
                    }
                }
                if status.state == .saved {
                    Text("Transcription starts on its own while the app is open.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if session.moments.isEmpty {
            Section {
                Text("No speech was found in this capture.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Moments

    @ViewBuilder
    private func momentSections(_ session: CaptureSession, summary: SpoolSessionSummary?) -> some View {
        if !session.moments.isEmpty {
            Section {
                Text("\(session.reviewedMomentCount) of \(session.moments.count) reviewed")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        ForEach(session.sortedMoments) { moment in
            MomentRow(moment: moment, summary: summary, player: player) { editing = $0 }
        }
        if let error = player.lastError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    /// Poems split off with *Split here* have no Moment; until the library (spec 012) they are reached here.
    @ViewBuilder
    private var splitOffSection: some View {
        let splitOff = poems.filter { $0.moment == nil }
        if !splitOff.isEmpty {
            Section("Split-off poems") {
                ForEach(splitOff) { poem in
                    Button {
                        editing = poem
                    } label: {
                        Label(poem.title ?? poem.body.split(separator: "\n").first.map(String.init) ?? "",
                              systemImage: "pencil")
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// D-024 layout: one line per transcriber result, a blank line at a stanza gap; unsure words in orange.
    static func poem(_ segments: [TranscriptSegment], lowConfidence: Double,
                     config: LineBreakConfig = LineBreakConfig()) -> AttributedString {
        var text = AttributedString()
        var lastEnd: Double?
        for segment in segments.sorted(by: { $0.startSec < $1.startSec }) {
            if let lastEnd { text += AttributedString(segment.startSec - lastEnd >= config.stanzaGap ? "\n\n" : "\n") }
            for (index, word) in segment.timedTokens.enumerated() {
                if index > 0 { text += AttributedString(" ") }
                var token = AttributedString(word.text)
                if let confidence = word.confidence, confidence < lowConfidence {
                    token.foregroundColor = .orange
                    token.underlineStyle = .single
                }
                text += token
            }
            lastEnd = max(lastEnd ?? segment.endSec, segment.endSec)
        }
        return text
    }

    // MARK: - DEBUG metrics (R8)

    #if DEBUG
    private func metricsSection(_ metrics: SessionMetrics, session: CaptureSession,
                                summary: SpoolSessionSummary?) -> some View {
        let capture = metrics.capture
        return Section("Metrics (DEBUG)") {
            LabeledContent("Audio", value: CaptureFormat.seconds(metrics.audioSec))
            LabeledContent("Capture", value: CaptureFormat.seconds(capture?.durationSec))
            LabeledContent("Stopped", value: Self.time(capture?.stoppedAt))
            LabeledContent("Foregrounded", value: Self.time(capture?.foregroundedAt))
            LabeledContent("Transcription", value: "\(Self.time(metrics.transcriptionStartedAt)) → "
                           + Self.time(metrics.readyAt))
            LabeledContent("Job", value: CaptureFormat.seconds(metrics.jobSec))
            LabeledContent("Latency", value: CaptureFormat.seconds(metrics.latencySec))
            LabeledContent("Latency ÷ audio (AC2 ≤ 1)",
                           value: metrics.latencyRatio.map { String(format: "%.3f", $0) } ?? "–")
            LabeledContent("Battery", value: "\(Self.battery(capture?.start)) → \(Self.battery(capture?.stop))")
            LabeledContent("Battery drop (AC3 ≤ 10 %)",
                           value: capture?.batteryDrop.map { String(format: "%.1f %%", $0 * 100) } ?? "–")
            LabeledContent("Thermal", value: "\(capture?.start.thermalState ?? "–") → "
                           + (capture?.stop?.thermalState ?? "–"))
            LabeledContent("Audio kept", value: session.audioDeleted ? "no" : "yes")
            LabeledContent("Failed attempts", value: "\(session.attempts)")
            if let summary, summary.hasTranscript {
                ShareLink(item: summary.session.transcriptURL) {
                    Label("Export transcript.json", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private static func time(_ date: Date?) -> String {
        date?.formatted(date: .omitted, time: .standard) ?? "–"
    }

    private static func battery(_ snapshot: PowerSnapshot?) -> String {
        guard let snapshot else { return "–" }
        let level = snapshot.batteryLevel.map { String(format: "%.0f %%", $0 * 100) } ?? "?"
        return "\(level) \(snapshot.batteryState.rawValue)"
    }
    #endif
}
