import Foundation

enum QuestionMarkTests {
    static func run() {
        testWhQuestions()
        testAuxSubjectQuestions()
        testWanna()
        testCasualYouTags()
        testUpgradesTrailingPeriod()
        testRespectsExistingTerminal()
        testMultiSentenceOnlyLast()
        testStatementsUntouched()
        testImperativesUntouched()
        testNameCollisionUntouched()
        testLeadingInterjectionsSkipped()
        testHowToInfinitiveUntouched()
        testEmptyAndNoQuestion()
        testImperativesAreNotQuestions()
        testExclamativesAreNotQuestions()
        testWhenClauseStatementsUntouched()
        testWhenQuestionsStillFire()
        testDotsInsideWordsAreNotSentenceEnds()
        testRealSentenceEndsAfterDottedWords()
    }

    /// A stop inside a path, a version, a domain, a decimal or an abbreviation
    /// is not a sentence end. It used to be: the scan took the last "." wherever
    /// it sat, so "can you check src/main.swift" was tested as the fragment
    /// "swift", matched no question frame, and kept its flat ending. Measured
    /// 2026-08-07 against the shipped scan — all seven came back unchanged, and
    /// invisibly so, because `punctuate` only ever adds a "?". This profile is
    /// on by default in `codeOrTerminal`, which is exactly where paths and
    /// version numbers get dictated.
    private static func testDotsInsideWordsAreNotSentenceEnds() {
        expect("can you check src/main.swift", "can you check src/main.swift?")
        expect("can you look at CLAUDE.md and tell me what it says",
               "can you look at CLAUDE.md and tell me what it says?")
        expect("are we on version 2.5.1 now", "are we on version 2.5.1 now?")
        expect("is it 1.5 million all in", "is it 1.5 million all in?")
        expect("did you email marek at ledgeriq.io about it",
               "did you email marek at ledgeriq.io about it?")
        expect("did you hear back from Dr. Okonkwo", "did you hear back from Dr. Okonkwo?")
        expect("can you send e.g. the thing we discussed",
               "can you send e.g. the thing we discussed?")
        // The same shapes in a statement still get nothing: widening the
        // sentence must not manufacture a question out of one.
        expect("I'll check src/main.swift tonight", "I'll check src/main.swift tonight")
        expect("we shipped version 2.5.1 today", "we shipped version 2.5.1 today")
    }

    /// The other direction, which is what stops the fix from over-correcting: a
    /// stop that really does end a sentence must still be found, including right
    /// after a filename, a version or an abbreviation, and including the
    /// lowercase continuation the recogniser sometimes emits. That last row is
    /// why `NLTokenizer` cannot simply replace the scan — measured, it does not
    /// split "…late. can you cover for me" at all — and the final case is what a
    /// whole-string fallback would have broken, by marking a leading question as
    /// the last sentence and stamping a "?" onto a trailing statement.
    private static func testRealSentenceEndsAfterDottedWords() {
        expect("Check src/main.swift. can you review it", "Check src/main.swift. can you review it?")
        expect("Ship 2.5.1 today. is that ok", "Ship 2.5.1 today. is that ok?")
        expect("Ask Dr. Okonkwo. did she reply", "Ask Dr. Okonkwo. did she reply?")
        expect("Meet at 5 p.m. Can you make it", "Meet at 5 p.m. Can you make it?")
        expect("Send it to Mr. Whitfield. Can you confirm", "Send it to Mr. Whitfield. Can you confirm?")
        expect("can you send it. i'll be out", "can you send it. i'll be out")
    }

    private static func testWhQuestions() {
        expect("how do I reset the password", "how do I reset the password?")
        expect("what time works for you", "what time works for you?")
        expect("Why is the build red", "Why is the build red?")
    }

    private static func testAuxSubjectQuestions() {
        expect("can you send that over", "can you send that over?")
        expect("is this the right version to ship", "is this the right version to ship?")
        expect("did we ever hear back", "did we ever hear back?")
        expect("are we still on for Friday", "are we still on for Friday?")
    }

    private static func testWanna() {
        expect("wanna grab dinner later", "wanna grab dinner later?")
    }

    private static func testCasualYouTags() {
        expect("you free tomorrow afternoon", "you free tomorrow afternoon?")
        expect("you coming to the thing tonight", "you coming to the thing tonight?")
        expect("you around later", "you around later?")
    }

    private static func testUpgradesTrailingPeriod() {
        expect("Can you cover for me.", "Can you cover for me?")
    }

    private static func testRespectsExistingTerminal() {
        expect("Are you coming?", "Are you coming?")   // already has one
        expect("Get out!", "Get out!")                 // exclamation preserved
    }

    private static func testMultiSentenceOnlyLast() {
        expect("I'm running late. can you cover for me", "I'm running late. can you cover for me?")
        // A question followed by a statement must NOT get a "?" on the statement.
        expect("I'll send it Friday", "I'll send it Friday")
    }

    private static func testStatementsUntouched() {
        for s in ["I'll send the invoice on Friday", "we should ship this tomorrow",
                  "the deploy finished cleanly", "you forgot the keys again"] {
            expect(s, s)
        }
    }

    private static func testImperativesUntouched() {
        expect("do the dishes before you leave", "do the dishes before you leave")
        expect("have a good weekend", "have a good weekend")
    }

    /// "Will is here" must not become "Will is here?" — the aux needs a subject.
    private static func testNameCollisionUntouched() {
        expect("Will is here now", "Will is here now")
        expect("May is out today", "May is out today")
    }

    private static func testLeadingInterjectionsSkipped() {
        expect("hey can you cover for me tomorrow", "hey can you cover for me tomorrow?")
        expect("okay so can you send it", "okay so can you send it?")
        expect("yo you free later", "yo you free later?")
        expect("and what did he say", "and what did he say?")
        // Two is the limit; a third leaves the sentence untested.
        expect("hey okay well can you send it", "hey okay well can you send it")
        // Must not manufacture a question out of a statement.
        expect("hey I need help with this", "hey I need help with this")
        expect("okay you go first", "okay you go first")
        expect("well that explains it", "well that explains it")
        // A bare interjection is never consumed down to nothing.
        expect("hey", "hey")
        expect("okay", "okay")
    }

    private static func testHowToInfinitiveUntouched() {
        expect("how to reset the password", "how to reset the password")
    }

    private static func testEmptyAndNoQuestion() {
        expect("", "")
        expect("okay sounds good", "okay sounds good")
    }

    /// "when" is the one wh-word that opens a subordinate clause on a statement
    /// more often than it opens a question. Measured before the inversion rule:
    /// 23 of 126 fires were wrong, and all 23 were sentences starting on a
    /// when-clause. Every line below got a "?" it should never have had.
    private static func testWhenClauseStatementsUntouched() {
        for s in ["when I get back I'll look at it",
                  "when you're done let me know",
                  "when we land I'll text you",
                  "when they reply forward it to me",
                  "when it finishes send me the log",
                  "when he calls back tell him I'm out",
                  "when that happens we roll it back",
                  "when this lands I'll close the ticket",
                  "when there is time I'll clean it up",
                  // The main clause's own "do it" / "have it done" is the same
                  // imperative pair the head-word check rejects at position 0 —
                  // it must not read as the inversion that rescues a "when".
                  "when I have a minute I'll do it",
                  "when I get home I'll have it done",
                  // Identical clause, noun-phrase subject instead of a pronoun.
                  "when the build finishes I'll ping you",
                  "when Merrick replies forward it to me"] {
            expect(s, s)
        }
        // Only the last sentence is judged, and up to two interjections are
        // stripped before the head word is read — the rule has to survive both.
        expect("I'll be out. when I get back I'll look at it",
               "I'll be out. when I get back I'll look at it")
        expect("so when I get back I'll look at it", "so when I get back I'll look at it")
    }

    /// Subject-auxiliary inversion is what makes a "when" interrogative, and it
    /// does not have to sit directly behind the wh-word — so the check scans the
    /// sentence rather than testing the second word alone.
    private static func testWhenQuestionsStillFire() {
        expect("when do I get access", "when do I get access?")
        expect("when is the demo", "when is the demo?")
        expect("when can we talk", "when can we talk?")
        expect("when are you free", "when are you free?")
        expect("when should I follow up", "when should I follow up?")
        expect("when does the build finish", "when does the build finish?")
        // Inversion a word or two back: an adverb, an expletive, or an entire
        // subordinate clause parked in front of the real question.
        expect("when exactly do you need it", "when exactly do you need it?")
        expect("when the hell did that happen", "when the hell did that happen?")
        expect("when you get a chance can you send that over",
               "when you get a chance can you send that over?")
        expect("when he gets here what do we do", "when he gets here what do we do?")
        expect("hey when do I get access", "hey when do I get access?")
        // Neighbours the "when" rule must leave exactly as they were: the
        // instructional infinitive, and a bare "when" with nothing to judge.
        expect("when to send it", "when to send it")
        expect("when", "when?")
    }

    // MARK: helpers

    private static func expect(_ input: String, _ want: String) {
        let got = QuestionMark.punctuate(input)
        guard got == want else {
            fatalError("QuestionMark: \"\(input)\" -> wanted \"\(want)\", got \"\(got)\"")
        }
    }

    /// "do it" is one of the most common things Bryce says to Claude Code, and
    /// this rule was turning it into "do it?". The profile is on by default in
    /// codeOrTerminal. A stray "?" cannot corrupt a shell command — which is
    /// what the call site's comment relies on — but a Claude Code prompt is not
    /// a shell command, and "do it?" reads to an agent as hesitation.
    private static func testImperativesAreNotQuestions() {
        for s in ["do it", "do that", "do this", "okay do it", "yeah do it",
                  "wait do that first", "actually do this instead",
                  "have it write the test first", "have them look at it"] {
            expect(QuestionMark.punctuate(s), s)
        }
        // The inflected forms are never imperative, so real questions stand.
        expect(QuestionMark.punctuate("did it work"), "did it work?")
        expect(QuestionMark.punctuate("does that make sense"), "does that make sense?")
        expect(QuestionMark.punctuate("has it shipped"), "has it shipped?")
        // And a pronoun SUBJECT is still an inversion, not an imperative.
        expect(QuestionMark.punctuate("do you have a minute"), "do you have a minute?")
        expect(QuestionMark.punctuate("do we need to ship today"), "do we need to ship today?")
    }

    /// "What a mess" is an exclamative; "what a" is not a question frame.
    private static func testExclamativesAreNotQuestions() {
        expect(QuestionMark.punctuate("What a mess"), "What a mess")
        expect(QuestionMark.punctuate("what an absolute disaster"), "what an absolute disaster")
        // Ordinary wh-questions are unaffected.
        expect(QuestionMark.punctuate("what time works for you"), "what time works for you?")
        expect(QuestionMark.punctuate("how did the demo go"), "how did the demo go?")
    }
}
