import AnamnesisKit
import SwiftData
import SwiftUI
import UIKit

/// One Moment in a session (spec 008 R5, spec 010 R1): the poem with unsure words, flags, Copy, the DEBUG excerpt,
/// and the review actions. A dismissed Moment collapses to its first line with Restore.
struct MomentRow: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    let moment: MomentRecord
    let summary: SpoolSessionSummary?
    let player: ExcerptPlayer
    /// Opens the poem editor (spec 011).
    let edit: (Poem) -> Void
    @State private var saveError: String?

    /// Words below this confidence are highlighted `[HYPOTHESIS]`; the hallucination flag uses its own, lower bar.
    static let lowConfidence = 0.5

    var body: some View {
        Section {
            if moment.review == .dismissed {
                dismissedContent
            } else {
                Text(CaptureSessionDetailView.poem(moment.segments, lowConfidence: Self.lowConfidence))
                    .textSelection(.enabled)
                if !moment.flags.isEmpty {
                    Label("May not be speech: " + moment.flags.map(Self.flagName).sorted().joined(separator: ", "),
                          systemImage: "exclamationmark.bubble")
                        .font(.caption).foregroundStyle(.orange)
                }
                reviewActions
                playbackActions
            }
            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Moment \(moment.index + 1) · \(CaptureFormat.duration(moment.startSec))"
                 + "–\(CaptureFormat.duration(moment.endSec))")
        }
    }

    // MARK: - Review (spec 010)

    @ViewBuilder
    private var reviewActions: some View {
        if moment.review == .saved {
            HStack {
                Label(savedText, systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.green)
                Spacer()
                if let poem = moment.poem {
                    Button("Edit poem", systemImage: "pencil") { edit(poem) }
                        .buttonStyle(.borderless)
                }
            }
        } else {
            HStack {
                Button("Save as poem", systemImage: "square.and.arrow.down") { saveAndEdit() }
                .buttonStyle(.borderless)
                Spacer()
                Button("Dismiss", systemImage: "xmark") { apply { moment.dismiss() } }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dismissedContent: some View {
        HStack {
            Text(moment.poemText.split(separator: "\n").first.map(String.init) ?? "")
                .lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            Button("Restore", systemImage: "arrow.uturn.backward") { apply { moment.restore() } }
                .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dismissed Moment \(moment.index + 1)")
    }

    /// A deleted poem leaves its Moment saved, with a note (spec 012 AC2).
    private var savedText: String {
        guard let poem = moment.poem else { return "Saved · poem deleted" }
        return "Saved as poem · " + poem.createdAt.formatted(date: .omitted, time: .shortened)
    }

    /// Saves at once so the decision outlives a kill (spec 010 AC2); a failed save is rolled back and shown.
    @discardableResult
    private func apply(_ change: () -> Void) -> Bool {
        change()
        do {
            try context.save()
            saveError = nil
            return true
        } catch {
            context.rollback()
            saveError = "Could not save: \(error.localizedDescription)"
            return false
        }
    }

    /// Spec 010 R2: the new poem opens in the editor.
    private func saveAndEdit() {
        var poem: Poem?
        guard apply({ poem = moment.saveAsPoem(in: context) }), let poem else { return }
        edit(poem)
    }

    // MARK: - Copy and excerpt (spec 008)

    private var playbackActions: some View {
        HStack {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = moment.poemText }
                .buttonStyle(.borderless)
            Spacer()
            if let summary, summary.hasAudio,
               let excerpt = ExcerptPlayer.Excerpt(startSec: moment.startSec, endSec: moment.endSec,
                                                   summary: summary) {
                let playing = player.playing == excerpt
                Button(playing ? "Stop" : "Play excerpt",
                       systemImage: playing ? "stop.fill" : "play.fill") { player.toggle(excerpt) }
                    .buttonStyle(.borderless)
                    .disabled(environment.capture.isCapturing)
            }
        }
    }

    private static func flagName(_ flag: HallucinationFlag) -> String {
        switch flag {
        case .repeatedNGramLoop: "repeated phrase"
        case .lowConfidence: "low confidence"
        case .noSpeechOverlap: "no speech detected"
        }
    }
}
