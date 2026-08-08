import Foundation

enum TranscriptTidierTests {
    static func run() {
        testCorrectionDoesNotDoubleTheFullStop()
        testFillers()
        testSafeRepeatedWordsAndStutters()
        testMeaningfulSpeechIsPreserved()
        testWhitespaceAndPunctuation()
        testCorrectionParsing()
        testCorrectionApplication()
        testReplacementTextIsNotProcessedAgain()
        testIdempotence()
        testSpokenIdentityMatchesParserDeduplication()
        testRepresentabilityRejectsWhatTheGrammarCannotExpress()
    }

    /// `identity(ofSpoken:)` must agree with what `parse` actually dedupes on,
    /// or a caller using it to decide "do I already have this rule?" will offer
    /// a duplicate that `parse` then silently discards.
    private static func testSpokenIdentityMatchesParserDeduplication() {
        let id = TranscriptTidier.CorrectionMapping.identity(ofSpoken:)
        expect(id("CAFE") == id("cafe\u{301}"), "case+diacritic folding disagrees")
        expect(id("  htmo  ") == id("htmo"), "identity is not trimmed")
        expect(id("resume") != id("resumes"), "identity over-folds distinct terms")
        // The behaviour it exists to mirror: parse keeps only the first of two
        // spoken forms that fold together.
        let parsed = TranscriptTidier.CorrectionMapping.parse("cafe -> coffee\nCAFE -> tea")
        expect(parsed.count == 1, "parse kept \(parsed.count) rules for one folded key")
        expect(parsed.first?.replacement == "coffee", "parse did not keep the first rule")
    }

    /// The grammar is line-oriented with no escapes, so some pairs cannot be
    /// written down at all. Anything that builds a rule line has to know that
    /// BEFORE offering it, not after.
    private static func testRepresentabilityRejectsWhatTheGrammarCannotExpress() {
        let ok = TranscriptTidier.CorrectionMapping.isRepresentable
        expect(ok("htmo", "HTML"), "an ordinary pair was rejected")
        expect(ok("c++", "C++"), "regex metacharacters are fine and must be allowed")
        expect(ok("get hub", "GitHub"), "a multi-word spoken form must be allowed")

        for (spoken, replacement, why) in [
            ("ht\nmo", "HTML", "newline in spoken splits into a second live rule"),
            ("htmo", "HT\nML", "newline in replacement truncates the rule"),
            ("a -> b", "HTML", "arrow in spoken yields three components"),
            ("htmo", "A -> B", "arrow in replacement yields three components"),
            ("a => b", "HTML", "alternate separator in spoken"),
            ("htmo", "A => B", "alternate separator in replacement"),
            ("a \u{2192} b", "HTML", "unicode arrow in spoken"),
            ("#tag", "HTML", "leading hash makes the line a comment"),
            ("", "HTML", "empty spoken"),
            ("htmo", "   ", "blank replacement"),
        ] {
            expect(!ok(spoken, replacement), "should have been rejected: \(why)")
        }

        // The property that matters: anything accepted here survives a round
        // trip through the real parser as exactly one rule.
        for (spoken, replacement) in [("htmo", "HTML"), ("c++", "C++"), ("get hub", "GitHub")] {
            let line = "\(spoken) -> \(replacement)"
            let parsed = TranscriptTidier.CorrectionMapping.parse(line)
            expect(parsed.count == 1, "\(line) parsed to \(parsed.count) rules")
            expect(parsed.first?.spoken == spoken && parsed.first?.replacement == replacement,
                   "\(line) did not round-trip")
        }
    }

    private static func testFillers() {
        let cases = [
            ("Um I think we should ship it.", "I think we should ship it."),
            ("I, uh, think this works", "I think this works"),
            ("I—uh—think this works", "I think this works"),
            ("uh uhm erm", ""),
            ("UH, hello", "hello"),
            ("That was yummy and the umbra moved.", "That was yummy and the umbra moved.")
        ]
        expectCases(cases)
    }

    private static func testSafeRepeatedWordsAndStutters() {
        let cases = [
            ("I I think the the build works", "I think the build works"),
            ("we we we should go", "we should go"),
            ("th- the release is ready", "the release is ready"),
            ("I w- want this", "I want this")
        ]
        expectCases(cases)
    }

    private static func testMeaningfulSpeechIsPreserved() {
        let unchanged = [
            "This is very very important.",
            "I like the first design.",
            "Use uh_value and umbraColor.",
            "Visit https://example.com/a--b.",
            "हाँ यह बहुत बहुत ज़रूरी है।",
            "The go-go release is intentional."
        ]
        for input in unchanged { expectEqual(TranscriptTidier.tidy(input), input) }
    }

    private static func testWhitespaceAndPunctuation() {
        let cases = [
            ("  hello   world  ", "hello world"),
            ("hello , world !", "hello, world!"),
            ("um, hello", "hello"),
            ("hello, uh", "hello")
        ]
        expectCases(cases)
    }

    private static func testCorrectionParsing() {
        let parsed = TranscriptTidier.CorrectionMapping.parse("""
        # Personal vocabulary
        mega phone -> Megaphone
        jason => JSON
        cube air → Kuber
        bad line
         -> missing
        MEGA PHONE -> duplicate
        too -> many -> arrows
        """)
        expectEqual(parsed, [
            .init(spoken: "mega phone", replacement: "Megaphone"),
            .init(spoken: "jason", replacement: "JSON"),
            .init(spoken: "cube air", replacement: "Kuber")
        ])
    }

    private static func testCorrectionApplication() {
        let mappings = TranscriptTidier.CorrectionMapping.parse("""
        mega phone -> Megaphone
        jason -> JSON
        see plus plus -> C++
        """)
        expectEqual(
            TranscriptTidier.tidy("Use mega   phone with jason and see plus plus.", corrections: mappings),
            "Use Megaphone with JSON and C++."
        )
        expectEqual(
            TranscriptTidier.tidy("The megaphone uses jsonValue.", corrections: mappings),
            "The megaphone uses jsonValue."
        )
    }

    private static func testReplacementTextIsNotProcessedAgain() {
        let mappings = TranscriptTidier.CorrectionMapping.parse("""
        visual studio code -> VS Code
        code -> CODE
        """)
        expectEqual(TranscriptTidier.tidy("Open visual studio code.", corrections: mappings), "Open VS Code.")
    }

    private static func testIdempotence() {
        let inputs = [
            "Um I I think, uh, th- the build works.",
            "This is very very important.",
            "hello , world !"
        ]
        for input in inputs {
            let once = TranscriptTidier.tidy(input)
            expectEqual(TranscriptTidier.tidy(once), once)
        }
    }

    private static func expectCases(_ cases: [(String, String)]) {
        for (input, expected) in cases {
            expectEqual(TranscriptTidier.tidy(input), expected)
        }
    }

    private static func expect(
        _ condition: Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !condition { fatalError("\(file):\(line): \(message)") }
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if actual != expected {
            fatalError("\(file):\(line): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
    }

    /// Measured on the real-voice regression set: "et cetera." -> "etc.." was
    /// the one case where corrections scored worse than leaving the text alone.
    private static func testCorrectionDoesNotDoubleTheFullStop() {
        let rules = TranscriptTidier.CorrectionMapping.parse("et cetera -> etc.")
        expectEqual(
            TranscriptTidier.apply(corrections: rules, to: "it runs in the future, et cetera."),
            "it runs in the future, etc."
        )
        // Mid-sentence the replacement keeps its own stop.
        expectEqual(
            TranscriptTidier.apply(corrections: rules, to: "logs, et cetera, and metrics"),
            "logs, etc., and metrics"
        )
        // An ellipsis is deliberate and must survive.
        expectEqual(TranscriptTidier.collapsingDoubledFullStop("wait... really"), "wait... really")
        expectEqual(TranscriptTidier.collapsingDoubledFullStop("done.. now"), "done. now")
    }
}
