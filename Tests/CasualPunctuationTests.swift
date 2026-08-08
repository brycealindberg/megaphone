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
        testNeverTouchesTextWithNoComma()
        testPolitenessParticleMustEndTheSentence()
        testOpenerCannotUnprotectAList()
        testListStartingOnAnOpenerWordKeepsEveryComma()
        testEnumerationGuardDoesNotShieldRealOpeners()
        testLengthGateCountsAllWhitespace()
        testStableOnOrdinaryText()
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
    ///
    /// The first fixture used to be "No worries man, all good", which is not a
    /// clause comma at all — it is a vocative, and as of 2026-08-05 it is kept.
    /// Swapped for an example that exercises what this test is actually named
    /// for. See `testDirectAddressCommaIsKept` for the measurement.
    private static func testLoneClauseComma() {
        expect(CasualPunctuation.lighten("finished the build, all good"), "finished the build all good")
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
    ///
    /// The example used to open "Yeah man," which is a vocative, not a discourse
    /// comma, and as of 2026-08-05 that one is kept. Swapped so this test
    /// exercises only what it is named for; the vocative case is kept below as a
    /// contrast, since the interaction is the interesting part.
    private static func testStackedInterjectionCommas() {
        expect(
            CasualPunctuation.lighten("Yeah for sure, honestly, let's link up later"),
            "Yeah for sure honestly let's link up later"
        )
        // Same shape with an address in front: the vocative survives, the
        // discourse comma after it still goes.
        expect(
            CasualPunctuation.lighten("Yeah man, for sure, let's link up later"),
            "Yeah man, for sure let's link up later"
        )
        expect(CasualPunctuation.lighten("nah bro, I'm good, catch you later"),
               "nah bro, I'm good catch you later")
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
        // CHANGED 2026-08-05, and deliberately: both of these used to assert that
        // the comma after a direct address is removed. Measured over 9,804 real
        // dictations, every comma sitting directly after an address term — man,
        // bro, sir, guys — is one Bryce KEEPS 85% of the time (man 89%, bro 82%,
        // sir 97%). The corpus even contains this fixture almost verbatim, kept:
        // "No worries brother, I want these calls to have the best vibes".
        // These fixtures carried no measurement of their own, so the data wins.
        // The other comma in the first line still goes.
        expect(
            CasualPunctuation.lighten("yeah man, for sure, let's link up"),
            "yeah man, for sure let's link up"
        )
        expect(CasualPunctuation.lighten("no worries man, all good"), "no worries man, all good")
        // The two neighbouring shapes stay stripped, because the same measurement
        // says he cuts those: a bare greeting (22% kept) and a trailing name (35%).
        expect(CasualPunctuation.lighten("Hey, how are you doing?"), "Hey how are you doing?")
        expect(
            CasualPunctuation.lighten("Thanks for reaching out, Sam."),
            "Thanks for reaching out Sam."
        )
        // But a name straight after a greeting is an address, and stays.
        expect(CasualPunctuation.lighten("Hey Dana, how's it going?"), "Hey Dana, how's it going?")
        expect(CasualPunctuation.lighten("Okay, bet I will"), "Okay bet I will")
    }

    /// This pass promises to only ever remove commas. It was quietly breaking
    /// that: `stripPolitenessCommas` ran `collapseSpaces` unconditionally, even
    /// when it replaced nothing, so merely having the toggle on rewrote
    /// whitespace on every dictation. In the terminal — where Bryce dictates
    /// most — that flattened code indentation and closed up " ; " and " : ".
    private static func testNeverTouchesTextWithNoComma() {
        for s in ["def run():\n    return 1",
                  "Steps:\n  1. open it\n  2. close it",
                  "cd /tmp ; ls -la",
                  "ratio is 3 : 4 in the config",
                  "has  two spaces here",
                  "all good no changes"] {
            expect(CasualPunctuation.lighten(s), s)
        }
    }

    /// The politeness rule fired on the particle OPENING a following clause,
    /// where the comma is required, and its `\s` even spanned newlines and
    /// joined two dictated lines. Sentence-final only now.
    private static func testPolitenessParticleMustEndTheSentence() {
        for s in ["The deck is ready, though the pricing page still needs a second pass",
                  "If you could review it by Friday, please let me know",
                  // Over the length gate on purpose: at 10 words the short-message rule
                  // strips this regardless, so a shorter fixture would not test rule 3.
                  "We should bring the charger, as well as the adapter and the spare cable",
                  "I'll send the revised deck over tomorrow,\nthough it may be late in the day"] {
            expect(CasualPunctuation.lighten(s), s)
        }
        // Still fires where it should.
        expect(CasualPunctuation.lighten("Let me know, please"), "Let me know please")
        expect(CasualPunctuation.lighten("Can you check it, please?"), "Can you check it please?")
    }

    /// The opener rule runs first and removes a comma, which could drop a real
    /// list from two commas (protected) to one (unprotected) — and then the
    /// short-message rule ate the survivor. The list test that was supposed to
    /// guard this used "Sorry," which is not an opener, so the path never ran.
    private static func testOpenerCannotUnprotectAList() {
        expect(
            CasualPunctuation.lighten("Okay, I grabbed eggs, milk and bread"),
            "Okay I grabbed eggs, milk and bread"
        )
        // The residual this test used to assert — "Word, Excel, and PowerPoint"
        // coming out as "Word Excel, and PowerPoint" — is closed as of
        // 2026-08-07. See testListStartingOnAnOpenerWordKeepsEveryComma.
        expect(CasualPunctuation.lighten("Word, Excel, and PowerPoint"), "Word, Excel, and PowerPoint")
    }

    /// CHANGED 2026-08-07, and deliberately. `testOpenerCannotUnprotectAList`
    /// used to assert the opposite of the first line here, as a KNOWN RESIDUAL:
    /// the opener rule was the one rule never given the `listProtected` verdict,
    /// so it ate the FIRST comma of any list whose first item is also an opener
    /// word — "word", "man", "no", "so", "well", "nice" are ordinary nouns and
    /// adverbs. Probed against the shipped file before the fix:
    ///
    ///     "Word, Excel, and PowerPoint"          -> "Word Excel, and PowerPoint"
    ///     "Word, Excel, PowerPoint and Outlook"  -> "Word Excel, PowerPoint and Outlook"
    ///     "Man, Kestrel, and Whitfield"          -> "Man Kestrel, and Whitfield"
    ///
    /// while the identical lists starting on a non-opener came through
    /// untouched, which is what makes this a defect in the rule rather than a
    /// judgement about lists. The old comment proposed splitting
    /// `leadingOpeners` by register; that is still unmeasured and still not
    /// done. This is the narrower fix: the opener rule now consults the same
    /// list verdict the short-message rule already had, and additionally
    /// requires the text to be nothing but short enumerated items.
    private static func testListStartingOnAnOpenerWordKeepsEveryComma() {
        expect(CasualPunctuation.lighten("Word, Excel, and PowerPoint"),
               "Word, Excel, and PowerPoint")
        // No Oxford comma: the coordinator joins the final pair instead.
        expect(CasualPunctuation.lighten("Word, Excel, PowerPoint and Outlook"),
               "Word, Excel, PowerPoint and Outlook")
        // Other openers that are ordinary words, and "or" as the coordinator.
        expect(CasualPunctuation.lighten("Man, Kestrel, and Whitfield"),
               "Man, Kestrel, and Whitfield")
        expect(CasualPunctuation.lighten("No, Kestrel, or Whitfield"),
               "No, Kestrel, or Whitfield")
        // Two-word items still read as items, and a numeric item is neutral.
        expect(CasualPunctuation.lighten("Word, Adobe Illustrator, and PowerPoint"),
               "Word, Adobe Illustrator, and PowerPoint")
        // A digit-initial item is neutral, not lowercase. (Written "365 Suite"
        // on purpose: a comma directly after a digit is read as a NUMBER comma
        // by every rule in this file, so "Word, 365, and Teams" never reaches
        // the list logic at all — a pre-existing property of the "1,000" guard.)
        expect(CasualPunctuation.lighten("Word, 365 Suite, and Teams"),
               "Word, 365 Suite, and Teams")
        // The control: the same shape not starting on an opener was always safe,
        // and must stay that way.
        expect(CasualPunctuation.lighten("Excel, Word, and PowerPoint"),
               "Excel, Word, and PowerPoint")
        // KNOWN RESIDUAL, asserted rather than left silent: an all-lowercase
        // list still loses its first comma, because dropping the capitalisation
        // signal is what would cost the two genuine openers in
        // testEnumerationGuardDoesNotShieldRealOpeners. Rarer than the shape
        // above — it needs the first item to be one of ~60 slang tokens AND the
        // whole list lowercase — and closing it needs a measurement.
        expect(CasualPunctuation.lighten("well, pump, or pipe"), "well pump, or pipe")
    }

    /// The other direction, which is the whole risk of the fix above: a genuine
    /// opener must still lose its comma, including when the sentence behind it
    /// contains a real list.
    private static func testEnumerationGuardDoesNotShieldRealOpeners() {
        expect(CasualPunctuation.lighten("Okay, so I think we should ship it"),
               "Okay so I think we should ship it")
        // Sentence that CONTAINS a list. The chunk "I grabbed eggs" is three
        // words, which is exactly why the item gate is two and not three.
        expect(CasualPunctuation.lighten("Okay, I grabbed eggs, milk, and bread"),
               "Okay I grabbed eggs, milk, and bread")
        // Short chunks, but no coordinating and/or/nor closing them, so this is
        // stacked discourse and not an enumeration.
        expect(CasualPunctuation.lighten("Yeah, for sure, I'll send it tonight"),
               "Yeah for sure I'll send it tonight")
        // Sentence punctuation inside a chunk means prose, not items.
        expect(
            CasualPunctuation.lighten("Also, this is a test to see if there's commas or not. Let me know, please."),
            "Also this is a test to see if there's commas or not. Let me know please."
        )
        // A number comma is not an item separator.
        expect(CasualPunctuation.lighten("Bet, it's 2,500 total"), "Bet it's 2,500 total")
        // The capitalisation signal. A dictation capitalises its first word
        // whatever that word is, so only the items BEHIND the first say
        // anything: lowercase ones mean the opener is an opener.
        expect(CasualPunctuation.lighten("Okay, eggs, milk, and bread"),
               "Okay eggs, milk, and bread")
        expect(CasualPunctuation.lighten("Anyway, gym, and groceries"),
               "Anyway gym, and groceries")
        // A greeting is carved back out of the guard even when the names behind
        // it are capitalised: the same 9,804-dictation measurement that keeps
        // "Hey Dana," says a BARE greeting comma is cut, 54 to 15.
        expect(CasualPunctuation.lighten("Hi, Dana, and Marek"), "Hi Dana, and Marek")
        expect(CasualPunctuation.lighten("Hey, Kestrel, and Whitfield"),
               "Hey Kestrel, and Whitfield")
    }

    /// The length gate split on spaces and newlines only, so a tab-separated
    /// line counted as one word and slipped under it.
    private static func testLengthGateCountsAllWhitespace() {
        let tabbed = "the quarterly report\tis attached, and the invoice follows next week"
        expect(CasualPunctuation.lighten(tabbed), tabbed)
    }

    /// `lighten` is ONCE-ONLY by contract, and this pins the boundary of that.
    ///
    /// It is stable for ordinary text, but NOT when the politeness rule removes
    /// a comma after the list decision has already been made: a second pass then
    /// sees a one-comma list, which the >=2 guard does not protect, and eats it.
    ///     "Grab eggs, milk or bread, please"
    ///       1x -> "Grab eggs, milk or bread please"
    ///       2x -> "Grab eggs milk or bread please"
    /// Not reachable in the app — `finishText` runs on exactly one of three
    /// mutually exclusive return paths, so `lighten` sees each dictation once
    /// (AppState.swift:3516, :3540, :3545). It IS reachable in an offline
    /// harness, so any corpus run must apply this to raw ASR exactly once or it
    /// will overstate removals.
    private static func testStableOnOrdinaryText() {
        for s in ["Hey Dana, how's it going?",
                  "no worries man, all good",
                  "Let me know, please",
                  "def run():\n    return 1",
                  "grab eggs, milk, and bread",
                  // Added 2026-08-07 with the enumeration guard: this one now
                  // comes back untouched, so it must survive a second pass too.
                  "Word, Excel, and PowerPoint"] {
            let once = CasualPunctuation.lighten(s)
            expect(CasualPunctuation.lighten(once), once)
        }
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
