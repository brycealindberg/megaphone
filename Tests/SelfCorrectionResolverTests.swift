import Foundation

enum SelfCorrectionResolverTests {
    static func run() {
        testFlagshipRestart()
        testRestartWithLetMe()
        testRestartWithIll()
        testValueSwapIsUntouched()
        testNumberValueSwapUntouched()
        testContentNoWaitUntouched()
        testPreservesEarlierSentence()
        testCollapsesChainedRestarts()
        testMarkerNeedsWordBoundary()
        testNoMarkerNoChange()
        testScratchThatRestart()
        testCapitalizationAtStart()
        testOpenerMustBeWholeWord()
    }

    /// The gap this exists to close.
    private static func testFlagshipRestart() {
        expect(
            SelfCorrectionResolver.resolve("let's meet at the office no wait let's do it over Zoom"),
            "Let's do it over Zoom"
        )
    }

    private static func testRestartWithLetMe() {
        expect(
            SelfCorrectionResolver.resolve("send it Friday no wait let me send it Monday"),
            "Let me send it Monday"
        )
    }

    private static func testRestartWithIll() {
        expect(
            SelfCorrectionResolver.resolve("I'll do it tomorrow scratch that I'll do it tonight"),
            "I'll do it tonight"
        )
    }

    /// The critical negative: a value swap must reach the model unchanged, or we
    /// would delete the sentence around it.
    private static func testValueSwapIsUntouched() {
        let s = "let's meet Thursday no wait Wednesday"
        expect(SelfCorrectionResolver.resolve(s), s)
    }

    private static func testNumberValueSwapUntouched() {
        let s = "call him at 3 no wait 4"
        expect(SelfCorrectionResolver.resolve(s), s)
    }

    /// "no wait" appearing as content, not a restart. No opener follows, so it
    /// must pass through.
    private static func testContentNoWaitUntouched() {
        let s = "tell them no wait for the check"
        expect(SelfCorrectionResolver.resolve(s), s)
    }

    private static func testPreservesEarlierSentence() {
        expect(
            SelfCorrectionResolver.resolve("I sent the email. Let's meet at the office no wait let's do Zoom"),
            "I sent the email. Let's do Zoom"
        )
    }

    private static func testCollapsesChainedRestarts() {
        expect(
            SelfCorrectionResolver.resolve("the office no wait the cafe no wait let's just do Zoom"),
            "Let's just do Zoom"
        )
    }

    private static func testMarkerNeedsWordBoundary() {
        // "startover" is not the phrase "start over".
        let s = "run the startover script then let's go"
        expect(SelfCorrectionResolver.resolve(s), s)
    }

    private static func testNoMarkerNoChange() {
        let s = "let's meet at the office and then grab lunch"
        expect(SelfCorrectionResolver.resolve(s), s)
    }

    private static func testScratchThatRestart() {
        expect(
            SelfCorrectionResolver.resolve("we should meet Tuesday scratch that we should meet Wednesday"),
            "We should meet Wednesday"
        )
    }

    private static func testCapitalizationAtStart() {
        // Restart at the very start of the utterance: the kept clause becomes
        // the sentence, so its first letter is capitalized.
        expect(
            SelfCorrectionResolver.resolve("go to the store no wait i'll go later"),
            "I'll go later"
        )
    }

    /// The opener must be a whole word: "letsomeone" must not read as "lets".
    private static func testOpenerMustBeWholeWord() {
        let s = "do it now no wait letsomeone else handle it"
        expect(SelfCorrectionResolver.resolve(s), s)
    }

    // MARK: helpers

    private static func expect(_ got: String, _ want: String) {
        guard got == want else {
            fatalError("SelfCorrectionResolver: wanted \"\(want)\", got \"\(got)\"")
        }
    }
}
