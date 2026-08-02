import Foundation

enum SpokenPunctuationTests {
    static func run() {
        testTrailingMarkAttaches()
        testMidUtteranceMarkAttaches()
        testTalkingAboutTheMarkIsLeftAlone()
        testRecogniserPunctuationIsAbsorbed()
        testNothingToAttachToIsLeftAlone()
        testUnrelatedTextIsUntouched()
        testIdempotent()
    }

    /// The reported case, and the one the model already handled — this must not
    /// regress it.
    private static func testTrailingMarkAttaches() {
        expect(SpokenPunctuation.substitute("is that done question mark") == "is that done?",
               got: SpokenPunctuation.substitute("is that done question mark"))
        expect(SpokenPunctuation.substitute("thanks exclamation mark") == "thanks!",
               got: SpokenPunctuation.substitute("thanks exclamation mark"))
        // The American form.
        expect(SpokenPunctuation.substitute("thanks exclamation point") == "thanks!",
               got: SpokenPunctuation.substitute("thanks exclamation point"))
    }

    /// The case the shipped pipeline got wrong: a mark in the middle stayed as
    /// literal words, and an exclamation became a floating " !".
    private static func testMidUtteranceMarkAttaches() {
        let s = SpokenPunctuation.substitute("sounds good exclamation mark let me know question mark")
        expect(s == "sounds good! let me know?", got: s)

        let two = SpokenPunctuation.substitute("wait what question mark that is wild exclamation mark")
        expect(two == "wait what? that is wild!", got: two)

        let yeah = SpokenPunctuation.substitute("Yeah exclamation mark love you")
        expect(yeah == "Yeah! love you", got: yeah)
        expect(!yeah.contains(" !"), "a floating mark survived: \(yeah)")
    }

    /// Someone describing punctuation is not dictating it. The model already
    /// gets this right, so the pass must not take it away.
    private static func testTalkingAboutTheMarkIsLeftAlone() {
        for s in [
            "he asked me to add a question mark at the end",
            "the question mark is missing",
            "put an exclamation mark there",
            "I removed that question mark",
            "my exclamation mark went missing",
            "add a trailing question mark",
        ] {
            expect(SpokenPunctuation.substitute(s) == s, got: SpokenPunctuation.substitute(s))
        }
        // Plural is a noun, never a command.
        expect(SpokenPunctuation.substitute("too many question marks") == "too many question marks",
               got: SpokenPunctuation.substitute("too many question marks"))
    }

    /// The recogniser often punctuates before this runs, so "thanks, exclamation
    /// mark" has to end up as "thanks!" and not "thanks,!".
    private static func testRecogniserPunctuationIsAbsorbed() {
        expect(SpokenPunctuation.substitute("thanks, exclamation mark") == "thanks!",
               got: SpokenPunctuation.substitute("thanks, exclamation mark"))
        expect(SpokenPunctuation.substitute("is that done. question mark") == "is that done?",
               got: SpokenPunctuation.substitute("is that done. question mark"))
        // And the trigger words themselves may arrive punctuated.
        expect(SpokenPunctuation.substitute("thanks exclamation mark.") == "thanks!",
               got: SpokenPunctuation.substitute("thanks exclamation mark."))
    }

    private static func testNothingToAttachToIsLeftAlone() {
        expect(SpokenPunctuation.substitute("question mark") == "question mark",
               got: SpokenPunctuation.substitute("question mark"))
        expect(SpokenPunctuation.substitute("exclamation mark why") == "exclamation mark why",
               got: SpokenPunctuation.substitute("exclamation mark why"))
        expect(SpokenPunctuation.substitute("") == "", got: SpokenPunctuation.substitute(""))
    }

    private static func testUnrelatedTextIsUntouched() {
        for s in [
            "ship the release on Wednesday",
            "the Jurassic period was long",
            "that is a comma splice",
            "full stop, no argument",
            "I need to dash to the shop",
        ] {
            expect(SpokenPunctuation.substitute(s) == s, got: SpokenPunctuation.substitute(s))
        }
    }

    /// It runs on the cleanup input AND the output, so running twice must be a
    /// no-op — see `deterministic-passes-must-run-on-the-cleanup-input`.
    private static func testIdempotent() {
        for s in ["thanks exclamation mark", "wait what question mark that is wild exclamation mark",
                  "he asked me to add a question mark at the end"] {
            let once = SpokenPunctuation.substitute(s)
            expect(SpokenPunctuation.substitute(once) == once, got: SpokenPunctuation.substitute(once))
        }
    }

    private static func expect(_ c: Bool, got: String, file: StaticString = #file, line: UInt = #line) {
        if !c { fatalError("\(file):\(line): got \"\(got)\"") }
    }

    private static func expect(_ c: Bool, _ m: String, file: StaticString = #file, line: UInt = #line) {
        if !c { fatalError("\(file):\(line): \(m)") }
    }
}
