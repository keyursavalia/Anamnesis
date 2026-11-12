import Foundation

/// Aggregates for one config over one category ("all" = every clip with a WER) (spec 004 R7).
public struct EvalSummary: Sendable, Equatable {
    public struct Stats: Sendable, Equatable {
        public var median: Double
        public var mean: Double
        public var min: Double
        public var max: Double
        public var count: Int

        public init?(_ values: [Double]) {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let middle = sorted.count / 2
            median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            mean = values.reduce(0, +) / Double(values.count)
            min = sorted[0]
            max = sorted[sorted.count - 1]
            count = values.count
        }
    }

    public var configName: String
    public var category: String
    public var jobs: Int
    public var failures: Int
    public var wer: Stats?
    public var lineBreakF1: Stats?
    public var realTimeFactor: Stats?
    public var textSecondsPerMinute: Stats?
    /// Share of rated clips with rating ≥ 4; nil when none is rated.
    public var fixableShare: Double?
}

public enum EvalReport {
    public static let allCategories = "all"

    /// Per config: "all" first, then each category present, alphabetically ("?" = no category).
    public static func summaries(_ run: EvalRun) -> [EvalSummary] {
        run.configs.flatMap { config -> [EvalSummary] in
            let results = run.results.filter { $0.configName == config.name }
            let categories = Set(results.map { $0.category ?? "?" }).sorted()
            return ([allCategories] + categories).map { category in
                let selected = category == allCategories ? results : results.filter { ($0.category ?? "?") == category }
                let ratings = selected.compactMap { run.rating(clipID: $0.clipID, configName: config.name) }
                return EvalSummary(
                    configName: config.name, category: category, jobs: selected.count,
                    failures: selected.filter { $0.error != nil }.count,
                    wer: .init(selected.compactMap { $0.scores?.wer?.wer }),
                    lineBreakF1: .init(selected.compactMap { $0.scores?.lineBreaks?.f1 }),
                    realTimeFactor: .init(selected.compactMap { $0.transcript?.metrics?.realTimeFactor }),
                    textSecondsPerMinute: .init(selected.compactMap { $0.scores?.hallucination?.textSecondsPerMinute }),
                    fixableShare: ratings.isEmpty ? nil
                        : Double(ratings.filter(\.isFixable).count) / Double(ratings.count))
            }
        }
    }

    /// `wer-<date>.csv` (R9): one row per job. Numbers use "." and no thousands separators.
    public static func werCSV(_ run: EvalRun) -> String {
        let header = ["clip", "category", "config", "wer", "cer", "ref_words", "hyp_words", "S", "D", "I",
                      "linebreak_f1", "linebreak_precision", "linebreak_recall", "text_sec_per_min", "flagged",
                      "audio_sec", "wall_sec", "rtf", "error"]
        let rows = run.results.map { result -> [String] in
            let scores = result.scores
            let wer = scores?.wer
            let metrics = result.transcript?.metrics
            return [result.clipID, result.category ?? "", result.configName, number(wer?.wer), number(scores?.cer),
                    int(wer?.referenceWords), int(wer?.hypothesisWords), int(wer?.substitutions), int(wer?.deletions),
                    int(wer?.insertions), number(scores?.lineBreaks?.f1), number(scores?.lineBreaks?.precision),
                    number(scores?.lineBreaks?.recall), number(scores?.hallucination?.textSecondsPerMinute),
                    int(scores?.flaggedSegments), number(metrics?.audioSec), number(metrics?.wallSec),
                    number(metrics?.realTimeFactor), result.error ?? ""]
        }
        return csv([header] + rows)
    }

    /// `ratings-<date>.csv` (R9).
    public static func ratingsCSV(_ run: EvalRun) -> String {
        let rows = run.ratings.map {
            [$0.clipID, $0.configName, String($0.rating), number($0.minutesToFix), $0.isFixable ? "1" : "0",
             $0.ratedAt.formatted(.iso8601)]
        }
        return csv([["clip", "config", "rating", "minutes_to_fix", "fixable", "rated_at"]] + rows)
    }

    static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? ""
    }

    private static func int(_ value: Int?) -> String { value.map(String.init) ?? "" }
}
