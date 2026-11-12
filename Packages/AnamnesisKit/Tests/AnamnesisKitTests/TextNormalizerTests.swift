import Testing
@testable import AnamnesisKit

@Suite("TextNormalizer")
struct TextNormalizerTests {
    @Test("normalizes per TESTING §4.2", arguments: [
        ("Do not go, gentle!", "do not go gentle"),
        ("  Tabs\tand\nnew  lines  ", "tabs and new lines"),
        ("don\u{2019}t", "don't"),
        ("don't stop", "don't stop"),
        ("'Tis the season", "tis the season"),
        ("the poets' words", "the poets words"),
        ("rock 'n' roll", "rock n roll"),
        ("well-known night\u{2014}and day\u{2013}light", "well known night and day light"),
        ("cafe\u{0301}", "café"),
        ("\u{FF21}\u{FF22}\u{FF23}", "abc"),
        ("\u{FB01}re", "fire"),
        ("3 roses, 12 thorns", "3 roses 12 thorns"),
        ("…!?;:\"()", "")
    ])
    func normalizes(_ input: String, _ expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }

    @Test("diacritics are kept, not folded")
    func keepsDiacritics() {
        #expect(TextNormalizer.words("café naïve") == ["café", "naïve"])
        #expect(TextNormalizer.normalize("café") != TextNormalizer.normalize("cafe"))
    }
}
