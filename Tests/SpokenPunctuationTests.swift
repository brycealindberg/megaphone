import Foundation

/// The measured defect: Bryce said "exclamation mark" and got nothing at all.
enum SpokenPunctuationTests {
    private static let corrections = [
        TranscriptTidier.CorrectionMapping(spoken: "exclamation mark", replacement: "!"),
        TranscriptTidier.CorrectionMapping(spoken: "et cetera", replacement: "etc."),
    ]

    static func run() {
        testTheMeasuredCase()
        testAbsorbsTheRecognisersTerminator()
        testMidSentenceKeepsTheFollowingSpace()
        testOnlyPunctuationMappingsAreClaimed()
        testIdempotent()
        testUntouchedWhenNotSpoken()
        testTheShapesItActuallyArrivesIn()
        testConsecutiveMarksCloseUp()
    }

    /// My first version passed its own tests and was still wrong on 196 real
    /// dictations, because it only absorbed a terminator BEFORE the phrase. In
    /// practice the phrase almost never arrives bare — it comes wrapped in the
    /// recogniser's pause commas, on both sides.
    private static func testTheShapesItActuallyArrivesIn() {
        expect(settle("It will, exclamation mark."), "It will!")
        expect(settle("Good job, Exclamation Mark."), "Good job!")
        expect(settle("Nevermind. Got it. Exclamation mark."), "Nevermind. Got it!")
        expect(
            settle("Just want to let you know, exclamation mark, hope you're doing well."),
            "Just want to let you know! hope you're doing well."
        )
    }

    private static func testConsecutiveMarksCloseUp() {
        expect(settle("I appreciate it, exclamation mark, exclamation mark."), "I appreciate it!!")
    }

    /// Real dictation, 2026-08-05. The whole point: the mark exists at all.
    private static func testTheMeasuredCase() {
        expect(
            settle("Hope everything is going great. and that you traveled safe. exclamation mark"),
            "Hope everything is going great. and that you traveled safe!"
        )
    }

    /// A plain substitution would leave "safe. !" — the recogniser has already
    /// closed the sentence, so the mark has to swallow that stop and close up.
    private static func testAbsorbsTheRecognisersTerminator() {
        expect(settle("we shipped it. exclamation mark"), "we shipped it!")
        expect(settle("we shipped it exclamation mark"), "we shipped it!")
        expect(settle("we shipped it! exclamation mark"), "we shipped it!")
    }

    private static func testMidSentenceKeepsTheFollowingSpace() {
        expect(settle("stop exclamation mark now we can ship"), "stop! now we can ship")
        expect(settle("line one exclamation mark\nline two"), "line one!\nline two")
    }

    /// "etc." is a word the model has no urge to delete, so it stays in the
    /// normal correction pass — handing the model corrected spellings measured
    /// materially worse (acc 0.8828 -> 0.8448).
    private static func testOnlyPunctuationMappingsAreClaimed() {
        expect(SpokenPunctuation.punctuationMappings(corrections).count, 1)
        expect(settle("we shipped it et cetera"), "we shipped it et cetera")
    }

    /// `finishText` runs the pre-model passes again on the way out, so this has
    /// to be a no-op the second time.
    private static func testIdempotent() {
        let once = settle("we shipped it. exclamation mark")
        expect(settle(once), once)
    }

    private static func testUntouchedWhenNotSpoken() {
        for s in ["nothing to do here", "an exclamation is not the phrase", ""] {
            expect(settle(s), s)
        }
        // No punctuation mappings configured at all: never touch the text.
        expect(
            SpokenPunctuation.settle("we shipped it. exclamation mark", corrections: []),
            "we shipped it. exclamation mark"
        )
    }

    // MARK: helpers

    private static func settle(_ s: String) -> String {
        SpokenPunctuation.settle(s, corrections: corrections)
    }

    private static func expect(_ got: String, _ want: String) {
        guard got == want else {
            fatalError("SpokenPunctuation: wanted \"\(want)\", got \"\(got)\"")
        }
    }

    private static func expect(_ got: Int, _ want: Int) {
        guard got == want else { fatalError("SpokenPunctuation: wanted \(want), got \(got)") }
    }
}
