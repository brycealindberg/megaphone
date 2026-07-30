import Foundation

/// Tests for lowercasing a dictation that continues an unfinished sentence.
/// Weighted toward what must NOT happen: the failure that matters is
/// de-capitalizing a name, not leaving a capital in place.
enum SentenceContinuationTests {
    // A slice of the real dictionary, including the entries that collide with
    // ordinary words ("Will", "Code", "Walk") — the reason function words have
    // to override the vocabulary.
    static let vocabulary = [
        "Devon", "Devon Blake", "Priya", "Priya Raman", "Devon.", "Claude",
        "Claude Code", "GitHub", "Hetzner", "Wispr Flow", "API", "SOW",
        "Will", "Code", "Walk", "OK", "Ghostty", "WhatsApp"
    ]

    static func run() {
        lowercasesAPlainContinuation()
        leavesAFinishedSentenceAlone()
        neverLowercasesAName()
        functionWordBeatsTheVocabulary()
        neverLowercasesIOrAcronyms()
        neverLowercasesDaysOrMonths()
        structuralPrefixesAreNotContinuations()
        openClausePunctuationContinues()
        missingCaretContextIsANoOp()
        preservesTheRestOfTheText()
    }

    // MARK: - the feature working

    static func lowercasesAPlainContinuation() {
        expect(
            "Meet at the office",
            before: "I was thinking we could ",
            equals: "meet at the office"
        )
        // The comma case: the model capitalizes after a comma too.
        expect("We should ship it", before: "Honestly, ", equals: "we should ship it")
        expect("Then we deploy", before: "First we test;", equals: "then we deploy")
        expect("First the tests", before: "Three things:", equals: "first the tests")
    }

    static func leavesAFinishedSentenceAlone() {
        expect("Meet at the office", before: "That works for me. ", equals: nil)
        expect("Meet at the office", before: "Does that work? ", equals: nil)
        expect("Meet at the office", before: "Let's go!", equals: nil)
        // A fresh line is a fresh sentence, so the newline must survive trimming.
        expect("Meet at the office", before: "Notes for today\n", equals: nil)
    }

    // MARK: - what must never happen

    static func neverLowercasesAName() {
        expect("Devon said he would", before: "I talked to ", equals: nil)
        expect("Claude wrote it", before: "Honestly ", equals: nil)
        expect("Hetzner is cheaper", before: "It turns out ", equals: nil)
        // Multi-word vocabulary entries protect their first word.
        expect("Wispr does this better", before: "Honestly ", equals: nil)
    }

    static func functionWordBeatsTheVocabulary() {
        // "Will", "Code" and "Walk" are all in the dictionary as capitalized
        // terms. As a continuation's first word they are still function words.
        expect("Will do it tomorrow", before: "I think we ", equals: "will do it tomorrow")
        expect("Code for that is done", before: "Let me check the ", equals: "code for that is done")
        expect("Walk to the park", before: "Let's take a ", equals: "walk to the park")
    }

    static func neverLowercasesIOrAcronyms() {
        expect("I will handle it", before: "If that works ", equals: nil)
        expect("I'm on it", before: "If that works ", equals: nil)
        expect("API keys are set", before: "Double check the ", equals: nil)
        expect("SOW is drafted", before: "The ", equals: nil)
        expect("GitHub is down", before: "Looks like ", equals: nil)
    }

    static func neverLowercasesDaysOrMonths() {
        expect("Monday works", before: "How about ", equals: nil)
        expect("May is booked", before: "Unfortunately ", equals: nil)
        expect("Friday if that's easier", before: "Or ", equals: nil)
    }

    static func structuralPrefixesAreNotContinuations() {
        // A list bullet starts a new item.
        expect("Wash the dishes", before: "- ", equals: nil)
        expect("Wash the dishes", before: "* ", equals: nil)
        // A shell prompt is not an unfinished sentence.
        expect("Run the tests", before: "~/Projects/megaphone % ", equals: nil)
        expect("Run the tests", before: "user@host:~$ ", equals: nil)
        // An opening quote takes a capital: he said, "We should go".
        expect("We should go", before: "He said, \"", equals: nil)
        expect("We should go", before: "(", equals: nil)
    }

    static func openClausePunctuationContinues() {
        expect("And the invoice", before: "Send the SOW ", equals: "and the invoice")
        expect("Or we skip it", before: "We ship today, ", equals: "or we skip it")
    }

    static func missingCaretContextIsANoOp() {
        let out = SentenceContinuation.adjust(
            "Meet at the office", textBeforeCaret: nil, protectedTerms: vocabulary
        )
        assertEqual(out, "Meet at the office", "nil caret context must not change the text")
        let empty = SentenceContinuation.adjust(
            "Meet at the office", textBeforeCaret: "   ", protectedTerms: vocabulary
        )
        assertEqual(empty, "Meet at the office", "whitespace-only context must not change the text")
    }

    static func preservesTheRestOfTheText() {
        // Only the very first letter changes — later sentences keep their caps,
        // and a trailing question mark from QuestionMark survives.
        expect(
            "Can you send that over? I need it today",
            before: "Quick one, ",
            equals: "can you send that over? I need it today"
        )
        // Leading quote: the first *letter* is what gets lowercased.
        expect("\"We should go\"", before: "he said ", equals: "\"we should go\"")
    }

    // MARK: - helpers

    /// `equals: nil` means "must come back untouched".
    private static func expect(
        _ text: String,
        before: String?,
        equals expected: String?
    ) {
        let out = SentenceContinuation.adjust(
            text, textBeforeCaret: before, protectedTerms: vocabulary
        )
        let want = expected ?? text
        assertEqual(out, want, "before=\(before.map { "\"\($0)\"" } ?? "nil") text=\"\(text)\"")
    }

    private static func assertEqual(
        _ actual: String, _ expected: String, _ label: String
    ) {
        guard actual == expected else {
            fatalError("SentenceContinuation: \(label)\n  expected: \"\(expected)\"\n  actual:   \"\(actual)\"")
        }
    }
}
