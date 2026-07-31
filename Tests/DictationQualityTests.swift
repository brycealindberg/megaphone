import Foundation

enum DictationQualityTests {
    static func run() {
        testUntouchedTextScoresPerfect()
        testOneWrongWordCosts()
        testEmptyAndPunctuationOnly()
        testScoreNeverGoesNegative()
        testFieldWithSurroundingTextStillScores()
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

    /// The defect the first live run exposed: the field contains the whole
    /// document, so comparing against all of it scored every real dictation
    /// 0.000. Only the region the dictation landed in counts.
    private static func testFieldWithSurroundingTextStillScores() {
        let doc = """
        MG-02 verification notes and a paragraph of earlier writing that has
        nothing to do with the dictation at all.

        Ask Marek Okonkwo whether the LedgerIQ migration finished.

        More trailing text underneath, also unrelated.
        """
        let untouched = DictationQuality.score(
            inserted: "Ask Marek Okonkwo whether the LedgerIQ migration finished.",
            edited: doc
        )
        expect(untouched.accuracy == 1.0, "text present verbatim in a document should score 1.0, got \(untouched.accuracy)")

        let oneFix = DictationQuality.score(
            inserted: "Ask Merrick Okonkwo whether the LedgerIQ migration finished.",
            edited: doc
        )
        expect(oneFix.accuracy < 1.0, "a real edit should cost something")
        expect(oneFix.accuracy > 0.5, "one word in eight should not read as total failure, got \(oneFix.accuracy)")
    }
}
