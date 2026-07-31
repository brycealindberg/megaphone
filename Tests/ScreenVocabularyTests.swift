import Foundation

enum ScreenVocabularyTests {
    static func run() {
        testNamesOnScreenBecomeTerms()
        testMultiWordNamesAlsoContributeTheirParts()
        testWindowChromeIsNotATerm()
        testDictionaryTermsAreNotDuplicated()
        testUnusualSpellingsAreCaught()
        testAddressesAndPathsAreRejected()
        testMidSentenceCapitalsAreCaught()
        testRealisticWindowSeparatesNamesFromChrome()
        testLimitIsRespected()
        testEmptyScreenYieldsNothing()
    }

    /// The reported case: a name is visible in the window and should be
    /// spelled the way the window spells it.
    private static func testNamesOnScreenBecomeTerms() {
        let screen = """
        Marek Vasiliev
        Thanks for the update, I'll review the onboarding script tonight.
        """
        let terms = ScreenVocabulary.terms(from: screen)
        expect(terms.contains("Marek Vasiliev"), "expected the full name, got \(terms)")
    }

    private static func testMultiWordNamesAlsoContributeTheirParts() {
        let terms = ScreenVocabulary.terms(from: "Message from Marek Vasiliev about the deposit.")
        expect(terms.contains("Marek Vasiliev"), "expected the whole name, got \(terms)")
        expect(terms.contains("Marek"), "expected the first name on its own, got \(terms)")
        // The whole name has to come first, or a tight limit keeps only halves.
        if let whole = terms.firstIndex(of: "Marek Vasiliev"), let part = terms.firstIndex(of: "Marek") {
            expect(whole < part, "expected the whole name ahead of its parts, got \(terms)")
        }
    }

    private static func testWindowChromeIsNotATerm() {
        let screen = """
        Inbox
        Search
        Settings
        Reply Forward Delete
        Today
        Monday
        The
        """
        let terms = ScreenVocabulary.terms(from: screen)
        expect(terms.isEmpty, "expected chrome to yield nothing, got \(terms)")
    }

    private static func testDictionaryTermsAreNotDuplicated() {
        let screen = "Kestrel and Marek Vasiliev are both mentioned here."
        let terms = ScreenVocabulary.terms(from: screen, excluding: ["kestrel", "Marek Vasiliev"])
        expect(!terms.contains { $0.lowercased() == "kestrel" }, "case-insensitive exclusion failed: \(terms)")
        expect(!terms.contains("Marek Vasiliev"), "exact exclusion failed: \(terms)")
    }

    /// Shapes a general speech model has no lexicon entry for. These are not
    /// names, so they are kept even without a leading capital.
    private static func testUnusualSpellingsAreCaught() {
        let terms = ScreenVocabulary.terms(from: "Wire the n8n webhook into LedgerIQ before Friday.")
        expect(terms.contains("n8n"), "expected the letter-digit token, got \(terms)")
        expect(terms.contains("LedgerIQ"), "expected the internal capital, got \(terms)")

        // SHOUTING and Ordinary Capitalisation are not unusual spellings.
        let plain = ScreenVocabulary.terms(from: "PLEASE READ Before Sending")
        expect(!plain.contains("PLEASE"), "all-caps should not qualify, got \(plain)")
    }

    private static func testAddressesAndPathsAreRejected() {
        let screen = "Email Marek at marek@example.com or see https://example.com/docs today."
        let terms = ScreenVocabulary.terms(from: screen)
        expect(!terms.contains { $0.contains("@") }, "an address became a term: \(terms)")
        expect(!terms.contains { $0.lowercased().contains(".com") }, "a domain became a term: \(terms)")
        expect(!terms.contains { $0.contains("/") }, "a path became a term: \(terms)")
    }

    /// A capital that is not starting a sentence is usually a proper noun.
    /// This is what catches an ordinary-looking company or tool name that no
    /// name tagger flags and no odd spelling gives away.
    private static func testMidSentenceCapitalsAreCaught() {
        let terms = ScreenVocabulary.terms(from: "He wants the Cadenza swap before the Fieldmark escrow clears.")
        expect(terms.contains("Cadenza"), "expected a mid-sentence capital, got \(terms)")
        expect(terms.contains("Fieldmark"), "expected a mid-sentence capital, got \(terms)")
        // A line-initial capital says nothing — that is where chrome lives.
        expect(!ScreenVocabulary.terms(from: "Compose\nArchive\nSnoozed").contains("Compose"),
               "a line-initial capital should not qualify")
        // A contraction whose stem is a stop word is not a name.
        expect(!ScreenVocabulary.terms(from: "ok I'll send the file over").contains("I'll"),
               "a contraction of a stop word should not qualify")
    }

    /// The whole point, measured on the shape `ScreenTextService` really
    /// returns: a window is mostly chrome, and the few names in it are the
    /// only thing worth spending a recogniser slot on.
    private static func testRealisticWindowSeparatesNamesFromChrome() {
        let window = """
        Slack
        Threads
        Drafts & sent
        #project-updates
        Alex Trelawney
        11:42 AM
        Marek Vasiliev came back on the onboarding bundle, he wants the Cadenza swap
        Jordan Whitaker
        11:44 AM
        ok I'll get the Kestrel config over to him today
        Message #project-updates
        Send
        """
        let terms = ScreenVocabulary.terms(from: window)

        // Whether the name tagger joins a pair is name-dependent — it joined
        // "Marek Vasiliev" and split "Alex Trelawney" — so what is asserted is
        // that every part is reachable. A surname is the half you actually
        // mishear, and it has to be there either way.
        for part in ["Alex", "Trelawney", "Marek", "Vasiliev", "Cadenza", "Kestrel"] {
            expect(terms.contains(part), "missing \(part) from \(terms)")
        }
        expect(terms.contains("Marek Vasiliev"), "expected the joined name, got \(terms)")
        for chrome in ["Slack", "Threads", "Drafts", "Send", "Message", "I'll"] {
            expect(!terms.contains(chrome), "chrome \(chrome) became a term: \(terms)")
        }
        expect(terms.count <= ScreenVocabulary.limit, "a single window overflowed the limit: \(terms.count)")
    }

    private static func testLimitIsRespected() {
        let screen = (1...80).map { "Person\($0) Lastname\($0) wrote a note." }.joined(separator: "\n")
        let terms = ScreenVocabulary.terms(from: screen, limit: 5)
        expect(terms.count <= 5, "limit ignored: \(terms.count) terms")
        expect(Set(terms).count == terms.count, "duplicates survived: \(terms)")
    }

    private static func testEmptyScreenYieldsNothing() {
        expect(ScreenVocabulary.terms(from: "").isEmpty, "empty text should yield nothing")
        expect(ScreenVocabulary.terms(from: "   \n\n  ").isEmpty, "whitespace should yield nothing")
        expect(ScreenVocabulary.terms(from: "Marek Vasiliev", limit: 0).isEmpty, "a zero limit should yield nothing")
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
