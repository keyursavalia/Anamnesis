#if DEBUG
import AnamnesisKit
import SwiftUI

// SPIKE: one transcript with metrics, poem layout, Moments and timed segments (spec 003 R10, R11).
struct TranscriptResultView: View {
    @Bindable var model: TranscriptionLabViewModel
    let transcript: Transcript
    @State private var exportURL: URL?

    var body: some View {
        List {
            metricsSection
            Section("Poem layout (pauses → line breaks)") {
                Text(transcript.poemText(config: model.lineBreakConfig)).textSelection(.enabled)
                Stepper(String(format: "Line gap %.1f s", model.lineBreakConfig.lineGap),
                        value: $model.lineBreakConfig.lineGap, in: 0.1...3, step: 0.1)
                Stepper(String(format: "Stanza gap %.1f s", model.lineBreakConfig.stanzaGap),
                        value: $model.lineBreakConfig.stanzaGap, in: 0.2...6, step: 0.1)
            }
            momentsSection
            segmentsSection
            Section {
                Button("Copy plain text", systemImage: "doc.on.doc") { model.copyText(poem: false) }
                Button("Copy poem layout", systemImage: "text.alignleft") { model.copyText(poem: true) }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Export JSON", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle(transcript.source)
        .task { exportURL = model.exportURL() }
    }

    private var metricsSection: some View {
        Section("Metrics") {
            LabeledContent("Locale · config", value: "\(transcript.locale) · \(transcript.config.module)")
            if let metrics = transcript.metrics {
                LabeledContent("Audio · wall",
                               value: String(format: "%.1f s · %.1f s", metrics.audioSec, metrics.wallSec))
                LabeledContent("Real-time factor",
                               value: metrics.realTimeFactor.map { String(format: "%.3f", $0) } ?? "–")
                LabeledContent("Peak footprint",
                               value: metrics.peakFootprintMB.map { String(format: "%.1f MB", $0) } ?? "–")
                LabeledContent("Asset status", value: metrics.assetStatus)
                LabeledContent("Analyzer format", value: metrics.analyzerFormat ?? "nil")
            }
            LabeledContent("Segments · flagged", value: "\(transcript.segments.count) · "
                           + "\(transcript.segments.filter { !$0.flags.isEmpty }.count)")
        }
    }

    private var momentsSection: some View {
        let moments = transcript.moments(config: model.momentConfig)
        return Section {
            ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(index + 1)  \(Self.time(moment.startSec)) – \(Self.time(moment.endSec))")
                        .font(.caption.monospacedDigit())
                    Text(moment.text).font(.callout).lineLimit(4)
                }
            }
            Stepper(String(format: "Moment gap %.1f s", model.momentConfig.momentGap),
                    value: $model.momentConfig.momentGap, in: 0.5...30, step: 0.5)
        } header: {
            Text("Moments (\(moments.count))")
        }
    }

    private var segmentsSection: some View {
        Section("Segments") {
            ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, flagged in
                let segment = flagged.segment
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.time(segment.startSec)) – \(Self.time(segment.endSec))"
                         + (segment.confidence.map { String(format: " · conf %.2f", $0) } ?? "")
                         + " · \(segment.words?.count ?? 0) words")
                        .font(.caption.monospacedDigit())
                    Text(segment.text).font(.callout)
                    if !flagged.flags.isEmpty {
                        Text(flagged.flags.map(\.rawValue).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private static func time(_ seconds: Double) -> String {
        String(format: "%d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}
#endif
