import Foundation

enum SpokenNameRepairTests {
    static func run() {
        testMeasuredMishearsAreRepaired()
        testOrdinaryDictationIsUntouched()
        testCorrectSpellingIsLeftAlone()
        testDictionaryTermsAreProtected()
        testLowercaseWordsAreNeverRepaired()
        testGrammarCapitalsAreNeverRepaired()
        testOrdinaryWordGuardDoesNotDisarmTheStem()
        testAcronymsAndShortSkeletonsNeverMatch()
        testShortAndEmptyInputsAreIgnored()
        testUnrelatedNamesNeverMatch()
        testPossessiveOnScreenNeverAddsOne()
        testPossessiveScreenTermStillSuppliesTheStem()
        testPlainSNamesAreNotStripped()
        testSpokenPossessiveIsUntouched()
        testBarePossessiveScreenTermIsIgnored()
    }

    /// Every case here is a transcript the real recogniser actually produced
    /// for `say`-synthesised audio, measured 2026-07-31. They are the reason
    /// this pass exists, so they are asserted verbatim.
    private static func testMeasuredMishearsAreRepaired() {
        expect(
            SpokenNameRepair.apply(
                "I sent the revised contract to Merrick Vasiliev this morning.",
                names: ["Marek Vasiliev", "Marek", "Vasiliev"]
            ) == "I sent the revised contract to Marek Vasiliev this morning.",
            "Merrick -> Marek"
        )
        expect(
            SpokenNameRepair.apply(
                "Please add Dana a Conquo to the call on Thursday.",
                names: ["Dana Okonkwo", "Dana", "Okonkwo"]
            ) == "Please add Dana Okonkwo to the call on Thursday.",
            "Dana a Conquo -> Dana Okonkwo"
        )
        // A name split into two words by the recogniser.
        expect(
            SpokenNameRepair.apply(
                "We should push the Ledger IQ update before the demo.",
                names: ["LedgerIQ"]
            ) == "We should push the LedgerIQ update before the demo.",
            "Ledger IQ -> LedgerIQ"
        )
    }

    /// The failure mode that matters: a repair pass that rewrites words the
    /// speaker really said is worse than no repair at all. A busy window
    /// supplies a lot of names, and none of them may touch ordinary dictation.
    private static func testOrdinaryDictationIsUntouched() {
        let names = [
            "Marek Vasiliev", "Marek", "Vasiliev", "Alex Trelawney", "Alex", "Trelawney",
            "Dana Okonkwo", "Dana", "Okonkwo", "LedgerIQ", "Cadenza", "Fieldmark",
            "Kestrel", "Marcus Whitfield", "Marcus", "Whitfield",
        ]
        let corpus = [
            "Can you send me the invoice before Friday please.",
            "I think we should ship the release on Wednesday once QA signs off.",
            "The deploy is green and the tests all passed.",
            "We need a webhook secret and a config file for the staging box.",
            "I'll take another look at the numbers tonight.",
            "The meeting got moved to Thursday afternoon at three.",
            "It looks like the cache is stale, let me clear it.",
            "The client wants a discount and a longer payment window.",
            "The API returns a 500 whenever the payload is empty.",
            "My flight got cancelled so I'll join remotely.",
            "The logs show a timeout on the third retry.",
            "Make sure the backup ran before you restart it.",
        ]
        for line in corpus {
            let out = SpokenNameRepair.apply(line, names: names)
            expect(out == line, "corrupted ordinary dictation:\n  in:  \(line)\n  out: \(out)")
        }
    }

    private static func testCorrectSpellingIsLeftAlone() {
        let text = "Marek Vasiliev already replied to the thread."
        expect(SpokenNameRepair.apply(text, names: ["Marek Vasiliev"]) == text, "already correct")
        // Differing only in case still counts as correct — casing is not this
        // pass's job, and rewriting it would fight the cleanup model.
        let lower = "ask kestrel for the config"
        expect(SpokenNameRepair.apply(lower, names: ["Kestrel"]) == lower, "case-only difference")
    }

    private static func testDictionaryTermsAreProtected() {
        let text = "We should push the Ledger IQ update."
        expect(
            SpokenNameRepair.apply(text, names: ["LedgerIQ"], protected: ["LedgerIQ"]) == text,
            "an explicit dictionary term outranks anything read off a window"
        )
    }

    /// The guard that makes the whole pass safe. Every false positive found
    /// while building this was a lowercase ordinary word that happened to sound
    /// like a name on screen, so only a word the recogniser already capitalised
    /// is eligible. Each line below was a real corruption before the guard.
    private static func testLowercaseWordsAreNeverRepaired() {
        let collisions: [(String, [String])] = [
            ("the marks are in from the exam", ["Marcus"]),
            ("send me the ledger for last quarter", ["LedgerIQ"]),
            ("the field mark on the survey is wrong", ["Fieldmark"]),
            ("I read the manual twice", ["Manuel"]),
            ("the cadence of the release is monthly", ["Cadenza"]),
            ("we walked through the Castro neighborhood", ["Kestrel"]),
        ]
        for (text, names) in collisions {
            let out = SpokenNameRepair.apply(text, names: names)
            expect(out == text, "corrupted a near-collision:\n  in:  \(text)\n  out: \(out)")
        }
    }

    /// The lowercase guard above is necessary but not sufficient, and this is
    /// the hole it left. It reads a capital as the recogniser's opinion that a
    /// word is a name — but **every sentence starts with a capital, and the
    /// pronoun "I" always carries one**, so at exactly the two positions
    /// dictation produces most often the guard waves ordinary words straight
    /// through to a screen term that happens to sound alike.
    ///
    /// Every line below is a real corruption taken from `transcripts.jsonl`,
    /// with the screen term that caused it: 45 of them in 3,565 dictations over
    /// the eleven days to 2026-08-18, about four a day, and seventeen went out
    /// through WhatsApp, iMessage and Discord to real people.
    private static func testGrammarCapitalsAreNeverRepaired() {
        let corruptions: [(String, [String])] = [
            // Sentence-initial capitals.
            ("Do we still need this?", ["Added"]),
            ("Did the messages she sent in?", ["Added"]),
            ("The one I should send.", ["Added"]),
            ("What do you think is best?", ["Without"]),
            ("They shipped it yesterday.", ["Tattoo"]),
            ("Then we can start the migration.", ["Ethan"]),
            ("All of the checks came back green.", ["Allow"]),
            ("Oh, that changes things.", ["YOOOO"]),
            ("It's like a 2 tab layout.", ["Audit"]),
            ("And yeah, definitely good to catch up.", ["Anita"]),
            ("There it is, right at the top.", ["Authority"]),
            ("You can send it whenever.", ["HeyCyan"]),
            // An interjection is the same shape: it opens a sentence, so it
            // collects a capital, and it is short enough to land near anything.
            ("Dang, yeah, it does go on tangents.", ["Waiting"]),
            // The pronoun "I", which is capitalised wherever it falls.
            ("OK, yes, I can do Monday or Tuesday morning PST.", ["Queen"]),
            ("I'll follow up with her.", ["Hello"]),
            ("I'll purchase released an MCP.", ["Allow"]),
            ("I think the account is still processing.", ["Waiting"]),
            ("I'm heading out in ten minutes.", ["Miami"]),
            ("I was testing the regex on that file.", ["a-zA-Z"]),
            ("How can I do number one for number two?", ["Added"]),
            // An ordinary word swallowed by a two-word window, after a name the
            // pass correctly left alone: "Priya was" -> "Priya Sam".
            ("Whatever Priya was texting in the past 3 days.", ["Priya Sam"]),
        ]
        for (text, names) in corruptions {
            let out = SpokenNameRepair.apply(text, names: names)
            expect(out == text, "rewrote a grammar capital:\n  in:  \(text)\n  out: \(out)")
        }
    }

    /// The second half of the same failure, found by replaying 3,565 real
    /// dictations against the fixed pass rather than by reading it. Dropping
    /// vowels is most of what makes an acronym, so an acronym's consonant
    /// skeleton is one character or none — and two empty skeletons compare
    /// equal, which is a match on nothing whatsoever. The capitalisation guard
    /// is no help at all here: an acronym really is uppercase.
    private static func testAcronymsAndShortSkeletonsNeverMatch() {
        let collisions: [(String, [String])] = [
            // Empty skeletons: every letter is a vowel or a semivowel.
            ("Can we fix the AI copy on that screen?", ["YOOOO"]),
            ("On a UI and UX standpoint, is it easy?", ["YOOOO"]),
            ("For the brief, I like A.", ["YOOOO"]),
            ("Yo, what do you mean?", ["YOOOO"]),
            // One-character skeletons.
            ("The keys were added in AWS.", ["a-zA-Z"]),
            ("How is everything been in AZ?", ["a-zA-Z"]),
            ("Can you update the agents MD file?", ["Mindi"]),
            ("I am going to show Ravi and Holly on a call.", ["Hello"]),
            ("Sorry, this Wi-Fi stuff is a headache.", ["YOOOO"]),
            ("Literally LOL.", ["Hello"]),
        ]
        for (text, names) in collisions {
            let out = SpokenNameRepair.apply(text, names: names)
            expect(out == text, "matched on a short skeleton:\n  in:  \(text)\n  out: \(out)")
        }
    }

    /// The ordinary-word guard must not reach past its job. A one-letter "a" is
    /// how the recogniser splits a name it could not place ("Dana a Conquo"),
    /// so it stays eligible even though it is an article — and a real name is
    /// still repaired at the start of a sentence, where the capital happens to
    /// be grammar but the word is nobody's function word.
    private static func testOrdinaryWordGuardDoesNotDisarmTheStem() {
        expect(
            SpokenNameRepair.apply(
                "Please add Dana a Conquo to the call.",
                names: ["Dana Okonkwo"]
            ) == "Please add Dana Okonkwo to the call.",
            "the article inside a split name stopped being repairable"
        )
        expect(
            SpokenNameRepair.apply("Merrick sent the contract over.", names: ["Marek"])
                == "Marek sent the contract over.",
            "a real name at the start of a sentence stopped being repaired"
        )
        expect(
            SpokenNameRepair.apply("Ledger IQ ships on Friday.", names: ["LedgerIQ"])
                == "LedgerIQ ships on Friday.",
            "a sentence-initial product name stopped being repaired"
        )
    }

    private static func testShortAndEmptyInputsAreIgnored() {
        expect(SpokenNameRepair.apply("", names: ["Marek"]) == "", "empty text")
        expect(SpokenNameRepair.apply("hello there", names: []) == "hello there", "no names")
        // Below the length floor a name is too easy to collide with.
        let text = "we can go now"
        expect(SpokenNameRepair.apply(text, names: ["Noa"]) == text, "short name ignored")
    }

    /// Names that share nothing acoustically must never swap for each other.
    private static func testUnrelatedNamesNeverMatch() {
        let text = "Alex Trelawney approved the budget yesterday."
        expect(
            SpokenNameRepair.apply(text, names: ["Marek Vasiliev", "Dana Okonkwo", "LedgerIQ"]) == text,
            "unrelated names matched"
        )
    }

    /// Reported 2026-08-08 from real pipeline history: two of twenty
    /// consecutive dictations had a correctly-heard name rewritten into the
    /// possessive, because a trailing "'s" is one edit away and the
    /// capitalisation guard cannot help when both forms are proper nouns.
    private static func testPossessiveOnScreenNeverAddsOne() {
        for (text, screen) in [
            ("Can you send Merrick an update in the group chat, please?", "Merrick's"),
            ("make sure what Alex and Whitfield talked about is in there", "Whitfield's"),
            // Meaning change, not just a spelling one.
            ("Trelawney is here today", "Trelawney's"),
            ("Okonkwo said she would come", "Okonkwo's"),
            // The curly apostrophe most UIs actually render.
            ("Trelawney is here today", "Trelawney\u{2019}s"),
        ] {
            expect(
                SpokenNameRepair.apply(text, names: [screen]) == text,
                "possessive screen term rewrote \"\(text)\""
            )
        }
    }

    /// The stem still has to work — stripping the possessive must not disarm
    /// the pass, only stop it inventing grammar.
    private static func testPossessiveScreenTermStillSuppliesTheStem() {
        expect(
            SpokenNameRepair.apply("send it to Merick today", names: ["Merrick's"])
                == "send it to Merrick today",
            "stem from a possessive screen term did not repair the mishear"
        )
    }

    /// Only an apostrophe form is stripped. A name that merely ends in s is a
    /// name.
    private static func testPlainSNamesAreNotStripped() {
        expect(
            SpokenNameRepair.apply("ask Jonnes about it", names: ["Jones"]) == "ask Jones about it",
            "a name ending in s stopped being repaired"
        )
        expect(
            SpokenNameRepair.apply("I met Travvis yesterday", names: ["Travis"]) == "I met Travis yesterday",
            "Travis stopped being repaired"
        )
    }

    /// The reverse direction never needed a guard and must stay that way: a
    /// spoken possessive short-circuits on the substring check.
    private static func testSpokenPossessiveIsUntouched() {
        let text = "I read Marek's note"
        expect(SpokenNameRepair.apply(text, names: ["Marek"]) == text, "spoken possessive was rewritten")
    }

    /// A screen term that is nothing but a possessive must not become an
    /// empty-string target.
    private static func testBarePossessiveScreenTermIsIgnored() {
        let text = "hello there"
        expect(SpokenNameRepair.apply(text, names: ["'s", "\u{2019}s", ""]) == text, "degenerate screen term matched")
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
