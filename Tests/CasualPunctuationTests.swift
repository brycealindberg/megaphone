import Foundation

enum CasualPunctuationTests {
    static func run() {
        testHisExample()
        testLeadingOpenerVariants()
        testMultiWordOpener()
        testLoneClauseComma()
        testTwoCommasFromOpenerPlusClause()
        testNeverTouchesQuestionMark()
        testNeverTouchesCapitalization()
        testKeepsNumberCommas()
        testKeepsListCommas()
        testStackedInterjectionCommas()
        testColonIntroducedListKeepsCommas()
        testLeavesLongSentenceCommaAlone()
        testDoesNotMatchOpenerAsPrefixOfAnotherWord()
        testEmptyAndNoComma()
        testAlsoIsAnOpener()
        testPolitenessCommas()
        testPolitenessRuleIsNotLengthGated()
        testPolitenessRuleTouchesNothingElse()
    }

    /// Bryce's own comma test came back unchanged because "Also," was not an
    /// opener and the message was over the short-message length gate.
    private static func testAlsoIsAnOpener() {
        expect(CasualPunctuation.lighten("Also, don't forget the invoice"),
               "Also don't forget the invoice")
        expect(CasualPunctuation.lighten("also, one more thing"), "also one more thing")
        // Not an opener when it is not opening.
        expect(CasualPunctuation.lighten("Send the contract and also, the invoice, tomorrow morning please"),
               "Send the contract and also, the invoice, tomorrow morning please")
    }

    private static func testPolitenessCommas() {
        expect(CasualPunctuation.lighten("Let me know, please"), "Let me know please")
        expect(CasualPunctuation.lighten("Send it over, though"), "Send it over though")
        expect(CasualPunctuation.lighten("Bring the charger, as well"), "Bring the charger as well")
    }

    /// The reported case end to end: 15 words, so the short-message rule cannot
    /// fire and both commas used to survive.
    private static func testPolitenessRuleIsNotLengthGated() {
        expect(
            CasualPunctuation.lighten("Also, this is a test to see if there's commas or not. Let me know, please."),
            "Also this is a test to see if there's commas or not. Let me know please."
        )
    }

    private static func testPolitenessRuleTouchesNothingElse() {
        // A number comma has no particle after it.
        expect(CasualPunctuation.lighten("wire 1,000 please"), "wire 1,000 please")
        // "please" not preceded by a comma is untouched.
        expect(CasualPunctuation.lighten("please send the deck over when you can"),
               "please send the deck over when you can")
        // A word that merely begins like a particle does not count. Kept long
        // enough that the short-message rule cannot fire and take the credit.
        expect(
            CasualPunctuation.lighten("the tone of the whole thing was, pleasant enough for the client call on Monday"),
            "the tone of the whole thing was, pleasant enough for the client call on Monday"
        )
        // Question marks and capitals are structurally out of reach.
        expect(CasualPunctuation.lighten("Can you check it, please?"), "Can you check it please?")
    }

    /// The reported case: "OK, bet I will" should read "OK bet I will".
    private static func testHisExample() {
        expect(CasualPunctuation.lighten("OK, bet I will"), "OK bet I will")
        expect(CasualPunctuation.lighten("Okay, bet I will"), "Okay bet I will")
    }

    private static func testLeadingOpenerVariants() {
        expect(CasualPunctuation.lighten("Yeah, sounds good"), "Yeah sounds good")
        expect(CasualPunctuation.lighten("Haha, that's wild"), "Haha that's wild")
        expect(CasualPunctuation.lighten("No, I can't make it"), "No I can't make it")
        expect(CasualPunctuation.lighten("So, what's the plan"), "So what's the plan")
    }

    private static func testMultiWordOpener() {
        expect(CasualPunctuation.lighten("No worries, all good"), "No worries all good")
        expect(CasualPunctuation.lighten("For sure, I'll be there"), "For sure I'll be there")
    }

    /// The comma is not after the opener but between two short clauses.
    private static func testLoneClauseComma() {
        expect(CasualPunctuation.lighten("No worries man, all good"), "No worries man all good")
        expect(CasualPunctuation.lighten("I'm down, let's do it"), "I'm down let's do it")
    }

    /// Opener comma AND a clause comma: the opener strip runs first, leaving a
    /// single comma for the short-clause strip.
    private static func testTwoCommasFromOpenerPlusClause() {
        expect(
            CasualPunctuation.lighten("Yeah for sure, I'll send it tonight"),
            "Yeah for sure I'll send it tonight"
        )
        expect(
            CasualPunctuation.lighten("Yeah, for sure, I'll send it tonight"),
            "Yeah for sure I'll send it tonight"
        )
    }

    /// The regression every prompt wording caused, made impossible by construction.
    private static func testNeverTouchesQuestionMark() {
        expect(CasualPunctuation.lighten("Are you coming tonight?"), "Are you coming tonight?")
        expect(CasualPunctuation.lighten("Wait, are you coming?"), "Wait are you coming?")
    }

    private static func testNeverTouchesCapitalization() {
        // Whatever case the cleanup produced is preserved exactly.
        expect(CasualPunctuation.lighten("ok, bet"), "ok bet")
        expect(CasualPunctuation.lighten("OK, BET"), "OK BET")
    }

    private static func testKeepsNumberCommas() {
        // A number comma is the only comma, but it is between digits, so the
        // short-clause rule must not remove it.
        expect(CasualPunctuation.lighten("send me 1,000"), "send me 1,000")
        expect(CasualPunctuation.lighten("Bet, it's 2,500 total"), "Bet it's 2,500 total")
    }

    private static func testKeepsListCommas() {
        // Two clause commas -> a list -> left alone by the lone-comma rule.
        expect(CasualPunctuation.lighten("grab eggs, milk, and bread"), "grab eggs, milk, and bread")
    }

    /// Found by the adversarial pass: stacked discourse commas, not a list, so
    /// they all go — but "and"/"or" lists are still protected (above).
    private static func testStackedInterjectionCommas() {
        expect(
            CasualPunctuation.lighten("Yeah man, for sure, let's link up later"),
            "Yeah man for sure let's link up later"
        )
        expect(CasualPunctuation.lighten("nah bro, I'm good, catch you later"),
               "nah bro I'm good catch you later")
    }

    private static func testLeavesLongSentenceCommaAlone() {
        let long = "After the meeting ends around three, I'll head over to grab some lunch"
        expect(CasualPunctuation.lighten(long), long)
    }

    /// "sorry" must not be read as the opener "so", and "note" must not be "no".
    private static func testDoesNotMatchOpenerAsPrefixOfAnotherWord() {
        expect(CasualPunctuation.lighten("Sorry, I missed that"), "Sorry I missed that")   // one clause comma, short -> stripped anyway, but NOT via the opener path
        expect(CasualPunctuation.lighten("Noted, will do"), "Noted will do")
        // The distinction matters when a second comma is present: opener path
        // must not fire on "sorry", leaving 2 commas -> list rule leaves both.
        expect(
            CasualPunctuation.lighten("Sorry, I grabbed eggs, milk and bread"),
            "Sorry, I grabbed eggs, milk and bread"
        )
    }

    /// A colon lead-in marks an enumeration, so its commas survive even with no
    /// coordinating "and". Regression: this exact line lost every comma.
    private static func testColonIntroducedListKeepsCommas() {
        expect(
            CasualPunctuation.lighten("Three things: the dictionary, the sounds, the double tap"),
            "Three things: the dictionary, the sounds, the double tap"
        )
        expect(
            CasualPunctuation.lighten("today: gym, groceries, laundry"),
            "today: gym, groceries, laundry"
        )
        // One comma is still a stray clause comma, colon or not.
        expect(CasualPunctuation.lighten("okay: all good, thanks"), "okay: all good thanks")
        // The colon has to precede the first comma to be a lead-in.
        expect(
            CasualPunctuation.lighten("dictionary, sounds, double tap: done"),
            "dictionary sounds double tap: done"
        )
        // And it must not resurrect the stacked-discourse case, which has none.
        expect(
            CasualPunctuation.lighten("yeah man, for sure, let's link up"),
            "yeah man for sure let's link up"
        )
        expect(CasualPunctuation.lighten("no worries man, all good"), "no worries man all good")
        expect(CasualPunctuation.lighten("Okay, bet I will"), "Okay bet I will")
    }

    private static func testEmptyAndNoComma() {
        expect(CasualPunctuation.lighten(""), "")
        expect(CasualPunctuation.lighten("all good no changes"), "all good no changes")
    }

    // MARK: helpers

    private static func expect(_ got: String, _ want: String) {
        guard got == want else {
            fatalError("CasualPunctuation: wanted \"\(want)\", got \"\(got)\"")
        }
    }
}
