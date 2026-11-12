import Foundation

/// Scoring normalization (TESTING §4.2, spec 004 R3). Decisions, fixed so scores stay comparable:
/// - Unicode NFKC, then lowercase: composes combining marks ("e" + U+0301 → "é") and folds compatibility forms
///   (full-width letters, ligatures). Diacritics are **kept**: "café" ≠ "cafe".
/// - Curly/modifier apostrophes become `'`; an apostrophe survives only **between** letters or digits
///   ("don't" stays, "'tis" → "tis", "poets'" → "poets").
/// - Hyphens and dashes separate words ("well-known" → "well known"); all other punctuation and symbols are
///   dropped as separators.
/// - Numbers are **not** spelled out: "3" ≠ "three" (the transcriber's choice counts as an error).
/// - Whitespace of any kind collapses; line breaks are ignored here and scored by `LineBreakScorer`.
public enum TextNormalizer {
    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{2018}", "\u{02BC}", "\u{FF07}"]

    public static func words(_ text: String) -> [String] {
        let characters = Array(text.precomposedStringWithCompatibilityMapping.lowercased())
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            if isWordCharacter(character) {
                current.append(character)
            } else if apostrophes.contains(character), !current.isEmpty,
                      index + 1 < characters.count, isWordCharacter(characters[index + 1]) {
                current.append("'")
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    public static func normalize(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
