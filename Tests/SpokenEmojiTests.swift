import Foundation

/// The trigger word is the whole safety story, so most of these prove the pass
/// does nothing rather than that it does something.
enum SpokenEmojiTests {
    static func run() {
        testTheReportedCases()
        testResolvesFromTheUnicodeNameTable()
        testDoesNothingWithoutTheTriggerWord()
        testLeavesAnUnknownNameAlone()
        testPrefersTheLongestName()
        testKeepsSurroundingTextAndPunctuation()
        testHandlesSeveralInOneDictation()
        testDoesNotReachPastPunctuation()
        testNeverResolvesANonEmojiCharacter()
        testEveryAliasResolves()
        testPunctuationIsNotStrandedAgainstTheGlyph()
    }

    /// The reported case: say the description, get the emoji.
    private static func testTheReportedCases() {
        expect(SpokenEmoji.substitute("laughing face emoji"), "😂")
        expect(SpokenEmoji.substitute("crying face emoji"), "😢")
        expect(SpokenEmoji.substitute("thumbs up emoji"), "👍")
        expect(SpokenEmoji.substitute("Laughing face emoji"), "😂")
        expect(SpokenEmoji.substitute("laughing face emojis"), "😂")
    }

    /// Anything Unicode names is available without an alias entry.
    private static func testResolvesFromTheUnicodeNameTable() {
        expect(SpokenEmoji.substitute("rocket emoji"), "🚀")
        expect(SpokenEmoji.substitute("brain emoji"), "🧠")
        expect(SpokenEmoji.substitute("thinking face emoji"), "🤔")
        // A text-presentation scalar gets the emoji selector so it renders in
        // colour rather than as a glyph.
        expect(SpokenEmoji.substitute("warning sign emoji"), "⚠️")
    }

    private static func testDoesNothingWithoutTheTriggerWord() {
        expect(SpokenEmoji.substitute("she had a crying face"), "she had a crying face")
        expect(SpokenEmoji.substitute("send me the rocket numbers"), "send me the rocket numbers")
        expect(SpokenEmoji.substitute("thumbs up everyone"), "thumbs up everyone")
        expect(SpokenEmoji.substitute(""), "")
    }

    private static func testLeavesAnUnknownNameAlone() {
        expect(SpokenEmoji.substitute("add an emoji"), "add an emoji")
        expect(SpokenEmoji.substitute("emoji"), "emoji")
        expect(SpokenEmoji.substitute("the quarterly report emoji"), "the quarterly report emoji")
    }

    /// "laughing face" must win over "face" — the loop tries the longest
    /// candidate first, so a two-word name is never split.
    private static func testPrefersTheLongestName() {
        expect(SpokenEmoji.substitute("I was laughing face emoji"), "I was 😂")
        expect(SpokenEmoji.substitute("red heart emoji"), "❤️")
        // "heart" alone is also an alias, so this proves the longer one wins.
        expect(SpokenEmoji.substitute("broken heart emoji"), "💔")
    }

    private static func testKeepsSurroundingTextAndPunctuation() {
        expect(SpokenEmoji.substitute("that's so funny laughing face emoji"), "that's so funny 😂")
        // Changed 2026-08-01: this asserted "😂." — keeping the full stop the
        // recogniser put after the spoken name. Bryce reported that as a defect
        // and the real pipeline confirmed it, so a trailing "." or "," at the end
        // of the text is now absorbed. "!" and "?" still survive, below.
        expect(SpokenEmoji.substitute("laughing face emoji."), "😂")
        expect(SpokenEmoji.substitute("fire emoji that build shipped"), "🔥 that build shipped")
        expect(SpokenEmoji.substitute("nice work party popper emoji!"), "nice work 🎉!")
    }

    /// The regression the lazy quantifier fixes: greedily, the first trigger was
    /// treated as one of the second phrase's name words and vanished.
    private static func testHandlesSeveralInOneDictation() {
        expect(SpokenEmoji.substitute("fire emoji and rocket emoji"), "🔥 and 🚀")
        expect(
            SpokenEmoji.substitute("thumbs up emoji then laughing face emoji"),
            "👍 then 😂"
        )
    }

    /// A name may not be read across punctuation, so a sentence that merely ends
    /// near the word "emoji" is safe.
    private static func testDoesNotReachPastPunctuation() {
        expect(SpokenEmoji.substitute("that's sad, emoji"), "that's sad, emoji")
        expect(SpokenEmoji.substitute("I'm done. emoji"), "I'm done. emoji")
    }

    /// The Unicode name table also holds every letter and digit. Nothing ASCII
    /// may ever come back through it.
    private static func testNeverResolvesANonEmojiCharacter() {
        expect(SpokenEmoji.substitute("digit one emoji"), "digit one emoji")
        expect(SpokenEmoji.substitute("latin small letter a emoji"), "latin small letter a emoji")
        expect(SpokenEmoji.substitute("space emoji"), "space emoji")
        expect(SpokenEmoji.emoji(for: "digit one") == nil, "a digit is not an emoji")
        expect(SpokenEmoji.emoji(for: "") == nil, "an empty name resolves to nothing")
    }

    /// Guards the table itself: an alias that no longer produces an emoji is a
    /// silent dead entry, since the ICU tier would just decline it too.
    private static func testEveryAliasResolves() {
        for (spoken, glyph) in SpokenEmoji.aliases {
            expect(!glyph.isEmpty, "alias \"\(spoken)\" has an empty replacement")
            expect(
                glyph.unicodeScalars.first?.properties.isEmoji == true,
                "alias \"\(spoken)\" is not an emoji"
            )
            expect(
                SpokenEmoji.substitute("\(spoken) emoji") == glyph,
                "alias \"\(spoken)\" does not survive substitution"
            )
        }
    }

    // MARK: helpers

    private static func expect(_ actual: String, _ expected: String) {
        if actual != expected {
            fatalError("SpokenEmoji: expected \"\(expected)\" but got \"\(actual)\"")
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError("SpokenEmoji: \(message)")
        }
    }

    /// The recogniser hears the pause before a spoken emoji name as a comma and
    /// closes the sentence after it, so replacing only the words left both marks
    /// stranded: "thanks so much folded hands emoji" became "Thanks so much, 🙏."
    /// Measured on real synthesized audio through the real recogniser.
    private static func testPunctuationIsNotStrandedAgainstTheGlyph() {
        expect(SpokenEmoji.substitute("Thanks so much, folded hands emoji.") == "Thanks so much 🙏",
               SpokenEmoji.substitute("Thanks so much, folded hands emoji."))
        expect(SpokenEmoji.substitute("That is hilarious laughing face emoji.") == "That is hilarious 😂",
               SpokenEmoji.substitute("That is hilarious laughing face emoji."))

        // It also runs on the model's output, where the trigger word is gone.
        expect(SpokenEmoji.substitute("Let's go 🚀.") == "Let's go 🚀",
               SpokenEmoji.substitute("Let's go 🚀."))

        // Mid-sentence punctuation is real and stays; "!" and "?" always stay.
        expect(SpokenEmoji.substitute("Sounds good 👍, see you tomorrow") == "Sounds good 👍, see you tomorrow",
               SpokenEmoji.substitute("Sounds good 👍, see you tomorrow"))
        expect(SpokenEmoji.substitute("Are you serious 😂?") == "Are you serious 😂?",
               SpokenEmoji.substitute("Are you serious 😂?"))
        expect(SpokenEmoji.substitute("Let's go 🚀!") == "Let's go 🚀!",
               SpokenEmoji.substitute("Let's go 🚀!"))

        // Text with no emoji at all is untouched, including its punctuation.
        expect(SpokenEmoji.substitute("Thanks so much, see you tomorrow.") == "Thanks so much, see you tomorrow.",
               SpokenEmoji.substitute("Thanks so much, see you tomorrow."))
    }

}
