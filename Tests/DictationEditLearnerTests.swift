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
        testWindowKeepsShortFieldsWhole()
        testWindowFindsDictationInsideAHugeBuffer()
        testWindowIgnoresTextBeyondTheSearchLimit()
        testWindowFallsBackToTheTail()
        testWindowPreservesTheLearnableCorrection()
    }

    // MARK: window

    private static func testWindowKeepsShortFieldsWhole() {
        let field = "git pull the branch"
        expect(DictationEditLearner.window(in: field, around: "get pull the branch"), field,
               "a field smaller than the span is returned untouched")
    }

    private static func testWindowFindsDictationInsideAHugeBuffer() {
        // The measured case: a terminal handing back its whole scrollback, with
        // the dictation at the caret — that is, near the end.
        let inserted = "please run git pull on the deploy branch"
        let field = String(repeating: "x", count: 2_000_000) + inserted + " and then wait"
        let w = DictationEditLearner.window(in: field, around: inserted)
        expect(w.contains(inserted), true, "the dictation survives the window")
        expect(w.count <= inserted.count + DictationEditLearner.windowMargin * 2 + 1, true,
               "the window is bounded, not the whole buffer")
    }

    private static func testWindowIgnoresTextBeyondTheSearchLimit() {
        // Buried further back than the caret could plausibly be: the tail cut
        // means it is not found, and the fallback must still be bounded rather
        // than handing back the buffer.
        let inserted = "please run git pull on the deploy branch"
        let field = inserted + String(repeating: "y", count: 2_000_000)
        let w = DictationEditLearner.window(in: field, around: inserted)
        expect(w.contains(inserted), false, "beyond the search limit it is not found")
        expect(w.count <= inserted.count + DictationEditLearner.windowMargin * 2 + 1, true,
               "the fallback is still bounded")
    }

    private static func testWindowFallsBackToTheTail() {
        // Nothing to anchor on — the dictation was rewritten past recognition.
        let field = String(repeating: "a", count: 5000) + "tail marker"
        let w = DictationEditLearner.window(in: field, around: "completely different words here")
        expect(w.hasSuffix("tail marker"), true, "falls back to the end of the field")
        expect(w.count < field.count, true, "still bounded")
    }

    private static func testWindowPreservesTheLearnableCorrection() {
        // The whole point: bounding must not cost a correction that would
        // otherwise have been learned.
        let inserted = "let's get pull the feature branch before lunch today"
        let edited = "let's git pull the feature branch before lunch today"
        let buffer = String(repeating: "noise ", count: 100_000) + edited
        let windowed = DictationEditLearner.window(in: buffer, around: inserted)
        let direct = DictationEditLearner.corrections(inserted: inserted, edited: edited)
        let viaWindow = DictationEditLearner.corrections(inserted: inserted, edited: windowed)
        expect(direct.first?.written, "git", "the unbounded diff learns git")
        expect(viaWindow.first?.written, direct.first?.written, "the windowed diff learns the same thing")
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
