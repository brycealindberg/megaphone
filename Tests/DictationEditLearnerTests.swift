import Foundation

enum DictationEditLearnerTests {
    static func run() {
        testLearnsRespelling()
        testLearnsCaseFix()
        testIgnoresContentRewrite()
        testIgnoresWordsThatAreNotAlike()
        testLearnsCloudToClaude()
        testIgnoresCommonWordSwaps()
        testIgnoresNumberFormatting()
        testIgnoresInflections()
        testIgnoresPureInsertionsAndDeletions()
        testDiscardsWholesaleRewrite()
        testUnchangedTextLearnsNothing()
        testFindsEditInsideALargerField()
        testCapsPerEdit()
        testLevenshteinEarlyExit()
    }

    /// The motivating case: "git pull" heard as "get pull", user fixes it.
    private static func testLearnsRespelling() {
        let got = DictationEditLearner.corrections(
            inserted: "can you get pull and rebase the branch",
            edited: "can you git pull and rebase the branch"
        )
        expect(got.count, 1, "one correction")
        expect(got.first?.heard, "get", "heard")
        expect(got.first?.written, "git", "written")
        expect(got.first?.isCaseOnly, false, "a respelling, not a case fix")
    }

    private static func testLearnsCaseFix() {
        let got = DictationEditLearner.corrections(
            inserted: "open claude code and check the logs",
            edited: "open Claude code and check the logs"
        )
        expect(got.count, 1, "one correction")
        expect(got.first?.written, "Claude", "written")
        expect(got.first?.isCaseOnly, true, "case only")
    }

    /// The dangerous case. Learning "Thursday -> Monday" would put a wrong fact
    /// in the dictionary and bias every later dictation.
    private static func testIgnoresContentRewrite() {
        let got = DictationEditLearner.corrections(
            inserted: "let's ship it on Thursday afternoon",
            edited: "let's ship it on Monday afternoon"
        )
        expect(got.count, 0, "Thursday -> Monday is a rewrite, not a mishearing")
    }

    private static func testIgnoresWordsThatAreNotAlike() {
        expect(DictationEditLearner.classify(heard: "git", written: "deploy") == nil, true,
               "unrelated words rejected")
        expect(DictationEditLearner.classify(heard: "invoice", written: "quote") == nil, true,
               "synonym swap rejected")
    }

    /// A common mishearing of a frequently dictated term (edit distance 2),
    /// found by the adversarial verification pass.
    private static func testLearnsCloudToClaude() {
        let c = DictationEditLearner.classify(heard: "cloud", written: "Claude")
        expect(c != nil, true, "cloud -> Claude is a mishearing worth learning")
        expect(c?.written, "Claude", "written form")
        // The looser budget must still reject genuinely different words.
        expect(DictationEditLearner.classify(heard: "invoice", written: "payment") == nil, true,
               "distant words still rejected")
    }

    private static func testIgnoresCommonWordSwaps() {
        expect(DictationEditLearner.classify(heard: "that", written: "this") == nil, true,
               "two common words is a meaning change")
        // But a common word corrected to a real term IS the case we want.
        expect(DictationEditLearner.classify(heard: "get", written: "git") != nil, true,
               "common -> specific is a mishearing")
    }

    private static func testIgnoresNumberFormatting() {
        expect(DictationEditLearner.classify(heard: "22", written: "23") == nil, true,
               "digits are a value change")
    }

    /// Found by running the real pipeline against live TextEdit: a plural is a
    /// grammar edit, and an inflected form teaches the recogniser nothing.
    private static func testIgnoresInflections() {
        for (heard, written) in [("branch","branches"), ("deploy","deployed"),
                                 ("run","running"), ("commits","commit")] {
            expect(DictationEditLearner.classify(heard: heard, written: written) == nil, true,
                   "\(heard) -> \(written) is an inflection, not a mishearing")
        }
        // Still catches the real thing, which is not a prefix relationship.
        expect(DictationEditLearner.classify(heard: "get", written: "git") != nil, true,
               "get -> git survives the inflection rule")
    }

    private static func testIgnoresPureInsertionsAndDeletions() {
        expect(DictationEditLearner.corrections(
            inserted: "ship the invoice",
            edited: "ship the invoice today"
        ).count, 0, "an appended word is writing, not correcting")

        expect(DictationEditLearner.corrections(
            inserted: "ship the invoice today",
            edited: "ship the invoice"
        ).count, 0, "a deleted word is editing, not correcting")
    }

    /// Many substitutions means the text was rewritten; mining it would produce
    /// nonsense pairs, so the whole edit is dropped.
    private static func testDiscardsWholesaleRewrite() {
        let got = DictationEditLearner.corrections(
            inserted: "alpha bravo charlie delta echo foxtrot",
            edited: "wolf xray yankee zulu victor uniform"
        )
        expect(got.count, 0, "a full rewrite yields nothing")
    }

    private static func testUnchangedTextLearnsNothing() {
        expect(DictationEditLearner.corrections(
            inserted: "the deploy finished cleanly",
            edited: "the deploy finished cleanly"
        ).count, 0, "no edit, no learning")
    }

    /// The field usually holds more than this one dictation.
    private static func testFindsEditInsideALargerField() {
        let got = DictationEditLearner.corrections(
            inserted: "then run get push to origin",
            edited: "Earlier notes I typed myself. then run git push to origin. And more after."
        )
        expect(got.count, 1, "found the substitution despite surrounding text")
        expect(got.first?.written, "git", "written")
    }

    private static func testCapsPerEdit() {
        // Four similar substitutions: within the discard limit, capped at 3.
        let got = DictationEditLearner.corrections(
            inserted: "kuber runs mautrix and psql and tmux daily",
            edited: "Kuber runs Mautrix and Psql and Tmux daily"
        )
        expect(got.count <= DictationEditLearner.maxCorrectionsPerEdit, true,
               "never more than the cap")
    }

    private static func testLevenshteinEarlyExit() {
        // Abandoned once over budget, so it returns limit+1 rather than the true distance.
        let d = DictationEditLearner.levenshtein(Array("abcdefgh"), Array("zzzzzzzz"), limit: 2)
        expect(d > 2, true, "early exit reports over-budget")
        expect(DictationEditLearner.levenshtein(Array("git"), Array("get"), limit: 1), 1, "git/get is 1")
    }

    // MARK: helpers

    private static func expect<T: Equatable>(_ got: T, _ want: T, _ what: String) {
        guard got == want else {
            fatalError("DictationEditLearner: \(what) — wanted \(want), got \(got)")
        }
    }
}
