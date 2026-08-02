import Foundation

/// The anchor word is the whole safety story, so most of these prove the pass
/// does nothing rather than that it does something.
enum SpokenEmailAddressTests {
    static func run() {
        testTheReportedCase()
        testSubsumesWhatTheModelAlreadyGetsRight()
        testOrdinaryProseIsUntouched()
        testSpokenDot()
        testPunctuationSurvivesOutsideTheAddress()
        testMultiWordLocalPartTakesOnlyTheLastToken()
        testCorrectionsWinBeforeThisPassRuns()
        testIdempotent()
    }

    /// The shape the cleanup model refuses: an address after "my email is".
    private static func testTheReportedCase() {
        expect(SpokenEmailAddress.assemble("My email is marek at kestrel.dev"),
               "My email is marek@kestrel.dev")
        expect(SpokenEmailAddress.assemble("my email is marekokonkwo at kestrel.dev"),
               "my email is marekokonkwo@kestrel.dev")
    }

    /// A deterministic pass must not lose the cases the model already handled.
    private static func testSubsumesWhatTheModelAlreadyGetsRight() {
        expect(SpokenEmailAddress.assemble("email me at support at example.com please"),
               "email me at support@example.com please")
        expect(SpokenEmailAddress.assemble("send it to hello at doubleclick dot ai"),
               "send it to hello@doubleclick.ai")
        expect(SpokenEmailAddress.assemble("contact jordan at fieldmark.io about it"),
               "contact jordan@fieldmark.io about it")
    }

    /// The refusals matter more than the conversions. Every one of these is a
    /// sentence a domain check alone would have corrupted.
    private static func testOrdinaryProseIsUntouched() {
        for sentence in [
            "let's meet at gmail.com headquarters",     // the model refuses this too
            "I'll be there at 5",
            "we looked at example.com yesterday",       // "looked" is no anchor
            "the outage at cloudflare.com lasted an hour",
            "meet me at the office",
            "",
        ] {
            expect(SpokenEmailAddress.assemble(sentence), sentence)
        }
        // An anchor alone is not enough — "me" is the object of "at", not a local part.
        expect(SpokenEmailAddress.assemble("email me at 5pm"), "email me at 5pm")
        // Nor is a domain-shaped token with no anchor anywhere.
        expect(SpokenEmailAddress.assemble("marek at kestrel.dev"), "marek at kestrel.dev")
    }

    private static func testSpokenDot() {
        expect(SpokenEmailAddress.assemble("email hello at doubleclick dot ai"),
               "email hello@doubleclick.ai")
        // An unknown TLD is not a domain.
        expect(SpokenEmailAddress.assemble("email hello at doubleclick dot banana"),
               "email hello at doubleclick dot banana")
    }

    private static func testPunctuationSurvivesOutsideTheAddress() {
        expect(SpokenEmailAddress.assemble("My email is marek at kestrel.dev."),
               "My email is marek@kestrel.dev.")
        expect(SpokenEmailAddress.assemble("Email marek at kestrel.dev, then call."),
               "Email marek@kestrel.dev, then call.")
    }

    /// A multi-word local part cannot be recovered — only the last token joins,
    /// which is honest about the limit rather than pretending to fix it. The
    /// real repair for a specific person is a `word_corrections` entry, and this
    /// pass runs AFTER those precisely so it cannot get in their way.
    private static func testMultiWordLocalPartTakesOnlyTheLastToken() {
        expect(SpokenEmailAddress.assemble("My email is Marek Hay Okonkwo at kestrel.dev"),
               "My email is Marek Hay Okonkwo@kestrel.dev")
    }

    /// The ordering that matters. A correction targeting the SPOKEN form has to
    /// win first; if this pass ran on the cleanup input it would rewrite " at "
    /// to "@" and the rule could never match again.
    private static func testCorrectionsWinBeforeThisPassRuns() {
        let rules = TranscriptTidier.CorrectionMapping.parse(
            "marek hay okonkwo at kestrel.dev -> marekokonkwo@kestrel.dev"
        )
        let heard = "Hey, my name is Marek. My email is Marek Hay Okonkwo at kestrel.dev. Hope you're doing well."
        // Production order: corrections, then finishText (which calls assemble).
        let corrected = TranscriptTidier.apply(corrections: rules, to: heard)
        expect(SpokenEmailAddress.assemble(corrected),
               "Hey, my name is Marek. My email is marekokonkwo@kestrel.dev. Hope you're doing well.")
        // The reverse order loses the rule entirely — this is what the comment
        // in finishText is protecting against.
        let assembledFirst = SpokenEmailAddress.assemble(heard)
        expect(TranscriptTidier.apply(corrections: rules, to: assembledFirst),
               "Hey, my name is Marek. My email is Marek Hay Okonkwo@kestrel.dev. Hope you're doing well.")
    }

    /// Runs on the cleanup input and again on its output, so twice must be a
    /// no-op — see `deterministic-passes-must-run-on-the-cleanup-input`.
    private static func testIdempotent() {
        for sentence in ["My email is marek at kestrel.dev", "email me at support at example.com please",
                         "let's meet at gmail.com headquarters"] {
            let once = SpokenEmailAddress.assemble(sentence)
            expect(SpokenEmailAddress.assemble(once), once)
        }
    }

    private static func expect(_ actual: String, _ expected: String, file: StaticString = #file, line: UInt = #line) {
        if actual != expected {
            fatalError("\(file):\(line): SpokenEmailAddress: expected \"\(expected)\" but got \"\(actual)\"")
        }
    }
}
