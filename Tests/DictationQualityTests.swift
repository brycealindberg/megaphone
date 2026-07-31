import Foundation

enum DictationQualityTests {
    static func run() {
        testUntouchedTextScoresPerfect()
        testOneWrongWordCosts()
        testEmptyAndPunctuationOnly()
        testScoreNeverGoesNegative()
    }

    private static func testUntouchedTextScoresPerfect() {
        let s = DictationQuality.score(
            inserted: "Ship the release on Wednesday.",
            edited: "Ship the release on Wednesday."
        )
        expect(s.accuracy == 1.0, "identical text should score 1.0, got \(s.accuracy)")
        expect(s.changedWords == 0, "no words should be changed")
        // Casing and punctuation are not accuracy defects.
        let cased = DictationQuality.score(inserted: "ship the release", edited: "Ship the release!")
        expect(cased.accuracy == 1.0, "case/punctuation should not count, got \(cased.accuracy)")
    }

    private static func testOneWrongWordCosts() {
        let s = DictationQuality.score(
            inserted: "ask Merrick about the invoice",
            edited: "ask Marek about the invoice"
        )
        expect(s.totalWords == 5, "expected 5 words, got \(s.totalWords)")
        expect(s.changedWords == 1, "expected 1 changed word, got \(s.changedWords)")
        expect(abs(s.accuracy - 0.8) < 0.0001, "expected 0.8, got \(s.accuracy)")
    }

    private static func testEmptyAndPunctuationOnly() {
        expect(DictationQuality.score(inserted: "", edited: "anything").accuracy == 1.0, "empty input is not a defect")
        expect(DictationQuality.score(inserted: "...", edited: "...").totalWords == 0, "punctuation is not words")
    }

    /// A user who replaces the text wholesale must not produce a negative score.
    private static func testScoreNeverGoesNegative() {
        let s = DictationQuality.score(
            inserted: "one two",
            edited: "completely different and much longer replacement text here"
        )
        expect(s.accuracy >= 0, "accuracy went negative: \(s.accuracy)")
        expect(s.changedWords <= s.totalWords, "changed words exceeded total: \(s.changedWords)/\(s.totalWords)")
    }

    private static func expect(_ c: Bool, _ m: String, file: StaticString = #file, line: UInt = #line) {
        if !c { fatalError("\(file):\(line): \(m)") }
    }
}
