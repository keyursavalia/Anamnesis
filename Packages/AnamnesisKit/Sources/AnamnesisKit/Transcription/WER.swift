/// One step of a reference ↔ hypothesis alignment, for the diff view (spec 004 R3).
public struct AlignedWord: Sendable, Equatable, Codable {
    public enum Operation: String, Sendable, Codable {
        case match, substitution, deletion, insertion
    }

    public var operation: Operation
    /// nil for an insertion.
    public var reference: String?
    /// nil for a deletion.
    public var hypothesis: String?
    /// Position of `hypothesis` in the hypothesis word list, to join confidences back on.
    public var hypothesisIndex: Int?
}

public struct WERResult: Sendable, Equatable, Codable {
    /// N: words in the normalized reference.
    public var referenceWords: Int
    public var hypothesisWords: Int
    public var substitutions: Int
    public var deletions: Int
    public var insertions: Int
    public var alignment: [AlignedWord]

    public var errors: Int { substitutions + deletions + insertions }

    /// (S + D + I) / N. 0 when both texts are empty; nil when only the reference is empty (category M clips:
    /// use the hallucination metric instead). Can exceed 1.
    public var wer: Double? {
        referenceWords > 0 ? Double(errors) / Double(referenceWords) : hypothesisWords == 0 ? 0 : nil
    }
}

/// Word error rate by word-level Levenshtein (TESTING §4.3).
public enum WER {
    public static func score(reference: String, hypothesis: String) -> WERResult {
        align(reference: TextNormalizer.words(reference), hypothesis: TextNormalizer.words(hypothesis))
    }

    /// Minimum-edit alignment. Ties prefer match/substitution, then deletion, then insertion, so the result
    /// is deterministic.
    public static func align(reference: [String], hypothesis: [String]) -> WERResult {
        let operations = editOperations(reference, hypothesis)
        var result = WERResult(referenceWords: reference.count, hypothesisWords: hypothesis.count,
                               substitutions: 0, deletions: 0, insertions: 0, alignment: [])
        var refIndex = 0
        var hypIndex = 0
        for operation in operations {
            switch operation {
            case .match, .substitution:
                if operation == .substitution { result.substitutions += 1 }
                result.alignment.append(AlignedWord(operation: operation, reference: reference[refIndex],
                                                    hypothesis: hypothesis[hypIndex], hypothesisIndex: hypIndex))
                refIndex += 1
                hypIndex += 1
            case .deletion:
                result.deletions += 1
                result.alignment.append(AlignedWord(operation: .deletion, reference: reference[refIndex]))
                refIndex += 1
            case .insertion:
                result.insertions += 1
                result.alignment.append(AlignedWord(operation: .insertion, hypothesis: hypothesis[hypIndex],
                                                    hypothesisIndex: hypIndex))
                hypIndex += 1
            }
        }
        return result
    }

    /// Character error rate over the normalized texts, spaces included (jiwer convention). Same nil rule as WER.
    public static func cer(reference: String, hypothesis: String) -> Double? {
        let ref = Array(TextNormalizer.normalize(reference))
        let hyp = Array(TextNormalizer.normalize(hypothesis))
        let errors = editOperations(ref, hyp).filter { $0 != .match }.count
        return ref.isEmpty ? (hyp.isEmpty ? 0 : nil) : Double(errors) / Double(ref.count)
    }

    static func editOperations<T: Equatable>(_ reference: [T], _ hypothesis: [T]) -> [AlignedWord.Operation] {
        let rows = reference.count + 1
        let columns = hypothesis.count + 1
        // Full matrix for backtracking; Test B clips are ≤ 90 s (≈ 300 words), so this stays small.
        var cost = [Int32](repeating: 0, count: rows * columns)
        for row in 0..<rows { cost[row * columns] = Int32(row) }
        for column in 0..<columns { cost[column] = Int32(column) }
        for row in 1..<max(rows, 1) {
            for column in 1..<max(columns, 1) {
                let diagonal = cost[(row - 1) * columns + column - 1]
                    + (reference[row - 1] == hypothesis[column - 1] ? 0 : 1)
                let deletion = cost[(row - 1) * columns + column] + 1
                let insertion = cost[row * columns + column - 1] + 1
                cost[row * columns + column] = min(diagonal, deletion, insertion)
            }
        }
        var operations: [AlignedWord.Operation] = []
        var row = reference.count
        var column = hypothesis.count
        while row > 0 || column > 0 {
            let here = cost[row * columns + column]
            if row > 0, column > 0 {
                let same = reference[row - 1] == hypothesis[column - 1]
                if here == cost[(row - 1) * columns + column - 1] + (same ? 0 : 1) {
                    operations.append(same ? .match : .substitution)
                    row -= 1
                    column -= 1
                    continue
                }
            }
            if row > 0, here == cost[(row - 1) * columns + column] + 1 {
                operations.append(.deletion)
                row -= 1
            } else {
                operations.append(.insertion)
                column -= 1
            }
        }
        return operations.reversed()
    }
}
