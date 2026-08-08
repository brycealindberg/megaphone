import Foundation

enum SpokenNameRepairTests {
    static func run() {
        testMeasuredMishearsAreRepaired()
        testOrdinaryDictationIsUntouched()
        testCorrectSpellingIsLeftAlone()
        testDictionaryTermsAreProtected()
        testLowercaseWordsAreNeverRepaired()
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
