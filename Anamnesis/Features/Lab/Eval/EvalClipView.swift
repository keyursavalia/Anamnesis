#if DEBUG
import AnamnesisKit
import SwiftUI

// SPIKE: one clip in one run: per-config scores, S/D/I diff with confidence shading, rating (spec 004 R7, R8).
struct EvalClipView: View {
    @Bindable var model: EvalViewModel
    let runID: String
    let clip: CorpusClip
    @State private var configName = ExperimentConfig.baseline.name
    @State private var rating = 4
    @State private var minutesToFix = ""

    var body: some View {
        if let run = model.run(id: runID) {
            List {
                Picker("Config", selection: $configName) {
                    ForEach(run.configs) { Text($0.name).tag($0.name) }
                }
                if let result = run.result(clipID: clip.id, configName: configName) {
                    scoresSection(result)
                    if let transcript = result.transcript, let wer = result.scores?.wer {
                        Section("Diff (red = deleted, orange = substituted, blue = inserted, yellow = conf < 0.5)") {
                            Text(EvalDiff.attributed(wer, confidences: EvalDiff.confidences(transcript)))
                                .textSelection(.enabled)
                        }
                        Section("Poem layout") {
                            Text(transcript.poemText(config: lineBreaks(run))).textSelection(.enabled)
                        }
                    }
                    ratingSection(run)
                } else {
                    Text("Not run yet").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(clip.id)
            .onChange(of: configName, initial: true) { loadRating(run) }
        }
    }

    private func scoresSection(_ result: EvalResult) -> some View {
        Section("Scores") {
            if let error = result.error { Text(error).foregroundStyle(.red) }
            if let wer = result.scores?.wer {
                LabeledContent("WER", value: wer.wer.map(EvalRunView.percent) ?? "n/a")
                LabeledContent("S · D · I / N", value: "\(wer.substitutions) · \(wer.deletions) · \(wer.insertions) "
                               + "/ \(wer.referenceWords)")
            }
            if let cer = result.scores?.cer { LabeledContent("CER", value: EvalRunView.percent(cer)) }
            if let breaks = result.scores?.lineBreaks {
                LabeledContent("Line breaks P · R · F1", value: [breaks.precision, breaks.recall, breaks.f1]
                    .map { $0.map { String(format: "%.2f", $0) } ?? "–" }.joined(separator: " · "))
            }
            if let metric = result.scores?.hallucination {
                LabeledContent("Text in non-speech", value: String(format: "%.1f s/min", metric.textSecondsPerMinute))
            }
            if let metrics = result.transcript?.metrics {
                LabeledContent("RTF", value: metrics.realTimeFactor.map { String(format: "%.3f", $0) } ?? "–")
            }
            LabeledContent("Flagged segments", value: "\(result.scores?.flaggedSegments ?? 0)")
        }
    }

    private func ratingSection(_ run: EvalRun) -> some View {
        Section {
            Stepper("Rating \(rating)", value: $rating, in: 1...5)
            TextField("Minutes to fix", text: $minutesToFix).keyboardType(.decimalPad)
            Button("Save rating", systemImage: "star") {
                model.setRating(runID: runID, clipID: clip.id, configName: configName, rating: rating,
                                minutesToFix: Double(minutesToFix.replacingOccurrences(of: ",", with: ".")))
            }
            .disabled(runID == model.activeRunID)
        } header: {
            Text("Rating")
        } footer: {
            Text("5 perfect · 4 a few fixes (< 2 min) · 3 significant (2–5 min) · 2 easier to retype · 1 unusable")
        }
    }

    private func lineBreaks(_ run: EvalRun) -> LineBreakConfig {
        run.configs.first { $0.name == configName }?.lineBreaks ?? LineBreakConfig()
    }

    private func loadRating(_ run: EvalRun) {
        let saved = run.rating(clipID: clip.id, configName: configName)
        rating = saved?.rating ?? 4
        minutesToFix = saved?.minutesToFix.map { String($0) } ?? ""
    }
}

enum EvalDiff {
    /// Confidence per normalized hypothesis token, or nil if tokenization does not line up with the WER input.
    static func confidences(_ transcript: Transcript) -> [Double?]? {
        let tokens = transcript.segments.flatMap(\.segment.timedTokens).flatMap { word in
            TextNormalizer.words(word.text).map { _ in word.confidence }
        }
        return tokens.count == TextNormalizer.words(transcript.plainText).count ? tokens : nil
    }

    static func attributed(_ wer: WERResult, confidences: [Double?]?) -> AttributedString {
        var text = AttributedString()
        for step in wer.alignment {
            var word: AttributedString
            switch step.operation {
            case .match:
                word = AttributedString(step.hypothesis ?? "")
            case .substitution:
                word = AttributedString("\(step.reference ?? "")→\(step.hypothesis ?? "")")
                word.foregroundColor = .orange
            case .deletion:
                word = AttributedString(step.reference ?? "")
                word.foregroundColor = .red
                word.strikethroughStyle = .single
            case .insertion:
                word = AttributedString(step.hypothesis ?? "")
                word.foregroundColor = .blue
                word.underlineStyle = .single
            }
            if let index = step.hypothesisIndex, let confidence = confidences?[index] ?? nil, confidence < 0.5 {
                word.backgroundColor = .yellow.opacity(0.35)
            }
            text += word + AttributedString(" ")
        }
        return text
    }
}
#endif
