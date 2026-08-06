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
        testIMeanRestart()
        testIMeanValueSwapUntouched()
        // trailing abandonment
        testTrailingScratchThatEmptiesTheUtterance()
        testTrailingScratchThatKeepsEarlierSentences()
        testTrailingMarkerNeedsAClauseBoundary()
        testTrailingMarkerIsASubsetOfMarkers()
        testTrailingMarkerToleratesMissingComma()
        testOtherTrailingAbandonPhrases()
        testDecimalsAndAbbreviationsSurviveTheDrop()
    }

    /// Found by review. `sentenceStart` used to scan back for any ".", so a
    /// decimal or an abbreviation INSIDE the abandoned sentence left a corrupted
    /// fragment — which is worse than either correct answer, because it pastes
    /// something the speaker never said.
    private static func testDecimalsAndAbbreviationsSurviveTheDrop() {
        expect(SelfCorrectionResolver.resolve("Charge 1.5 million, actually scratch that."), "")
        expect(SelfCorrectionResolver.resolve("Tell Dr. Smith tomorrow, scratch that."), "")
        expect(SelfCorrectionResolver.resolve("Email me at bryce at example.com, scratch that."), "")
        // A genuine earlier sentence is still kept, decimal and all. BOTH forms:
        // the version with a leading particle passed while the bare one was
        // broken, because the particle pushes the marker past the sentence
        // boundary and hid an off-by-one in the tokenizer scan.
        expect(
            SelfCorrectionResolver.resolve("Charge 1.5 million. Actually, scratch that."),
            "Charge 1.5 million."
        )
        expect(
            SelfCorrectionResolver.resolve("Charge 1.5 million. Scratch that."),
            "Charge 1.5 million."
        )
        expect(
            SelfCorrectionResolver.resolve("Send the invoice Friday. Scratch that."),
            "Send the invoice Friday."
        )
    }

    // MARK: - trailing abandonment

    /// The measured case, 2026-08-05. Three components each declined it and the
    /// text pasted verbatim: `ScratchCommandMatcher` needs the command to be the
    /// whole utterance, this resolver needed a clause after the marker, and the
    /// cleanup model only resolves value swaps.
    private static func testTrailingScratchThatEmptiesTheUtterance() {
        expect(SelfCorrectionResolver.resolve("OK, I'm dictating now, actually scratch that."), "")
        expect(SelfCorrectionResolver.resolve("OK, I'm dictating now, scratch that"), "")
    }

    /// The safety margin. A misfire can only ever cost the clause the marker is
    /// attached to, never a sentence the speaker already finished.
    private static func testTrailingScratchThatKeepsEarlierSentences() {
        expect(
            SelfCorrectionResolver.resolve("Send the invoice Friday. OK I'm dictating now, actually scratch that."),
            "Send the invoice Friday."
        )
    }

    /// "scratch that" as the speaker's actual words. "to" is neither a particle
    /// nor punctuation, so the marker belongs to the sentence.
    private static func testTrailingMarkerNeedsAClauseBoundary() {
        for s in ["I need to scratch that", "Remind me to scratch that", "Please scratch that"] {
            expect(SelfCorrectionResolver.resolve(s), s)
        }
    }

    /// Trailing markers are a strict subset of `markers`. A person trailing off
    /// with "I mean" is not deleting a sentence, and this path deletes sentences.
    private static func testTrailingMarkerIsASubsetOfMarkers() {
        for s in ["Let's meet Thursday, I mean.", "We should ship it, no wait.", "Call Dana, actually wait."] {
            expect(SelfCorrectionResolver.resolve(s), s)
        }
        for phrase in SelfCorrectionResolver.trailingAbandonMarkers {
            guard SelfCorrectionResolver.markers.contains(phrase) else {
                fatalError("SelfCorrectionResolver: \"\(phrase)\" is a trailing marker but not a marker")
            }
        }
    }

    /// The recogniser's comma placement is not reliable enough to require, so a
    /// bare particle is boundary enough.
    private static func testTrailingMarkerToleratesMissingComma() {
        expect(SelfCorrectionResolver.resolve("OK I'm dictating now actually scratch that"), "")
    }

    private static func testOtherTrailingAbandonPhrases() {
        expect(SelfCorrectionResolver.resolve("Book it for Tuesday, no scratch that"), "")
        expect(SelfCorrectionResolver.resolve("Book it for Tuesday. Actually, let me start over."), "Book it for Tuesday.")
    }

    /// "I mean" restart (found by the adversarial verification pass).
    private static func testIMeanRestart() {
        expect(
            SelfCorrectionResolver.resolve("let's go to the park I mean let's just stay home"),
            "Let's just stay home"
        )
    }

    /// "I mean" as a value swap: no clause opener follows, so it must pass
    /// through for the model to resolve, not get its sentence deleted.
    private static func testIMeanValueSwapUntouched() {
        let s = "let's meet Tuesday I mean Wednesday"
        expect(SelfCorrectionResolver.resolve(s), s)
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
