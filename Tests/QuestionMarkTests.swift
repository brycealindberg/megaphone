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

    // MARK: helpers

    private static func expect(_ input: String, _ want: String) {
        let got = QuestionMark.punctuate(input)
        guard got == want else {
            fatalError("QuestionMark: \"\(input)\" -> wanted \"\(want)\", got \"\(got)\"")
        }
    }
}
