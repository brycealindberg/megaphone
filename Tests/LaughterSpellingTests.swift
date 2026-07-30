import Foundation

/// The pass may only ever join adjacent laughter syllables. Most of these guard
/// the other direction — the things that look like laughter and are not.
enum LaughterSpellingTests {
    static func run() {
        testTheReportedCases()
        testKeepsTheCaseItFound()
        testJoinsAcrossACleanupComma()
        testJoinsAlreadyPartlyMergedLaughter()
        testLeavesALoneSyllableAlone()
        testNeverReachesInsideAnotherWord()
        testNeverJoinsAcrossALineOrSentence()
        testLeavesOrdinaryTextUntouched()
    }

    /// The reported case: spoken laughter is written as one word.
    private static func testTheReportedCases() {
        expect(LaughterSpelling.collapse("ha ha"), "haha")
        expect(LaughterSpelling.collapse("ha ha ha"), "hahaha")
        expect(LaughterSpelling.collapse("ha ha ha ha"), "hahahaha")
        expect(LaughterSpelling.collapse("that's amazing ha ha"), "that's amazing haha")
    }

    private static func testKeepsTheCaseItFound() {
        expect(LaughterSpelling.collapse("Ha ha"), "Haha")
        expect(LaughterSpelling.collapse("Ha ha ha that's wild"), "Hahaha that's wild")
        expect(LaughterSpelling.collapse("HA HA"), "HAHA")
        // Mixed case is neither a shout nor a sentence start: keep it plain.
        expect(LaughterSpelling.collapse("ha Ha"), "haha")
    }

    /// Smart Cleanup likes to punctuate the syllables apart. Joining across that
    /// comma is why this runs before the casual-chat comma pass, not after.
    private static func testJoinsAcrossACleanupComma() {
        expect(LaughterSpelling.collapse("Ha, ha"), "Haha")
        expect(LaughterSpelling.collapse("Ha, ha, that's wild"), "Haha, that's wild")
        expect(LaughterSpelling.collapse("ha,ha"), "haha")
    }

    private static func testJoinsAlreadyPartlyMergedLaughter() {
        expect(LaughterSpelling.collapse("haha ha"), "hahaha")
        expect(LaughterSpelling.collapse("ha haha"), "hahaha")
        expect(LaughterSpelling.collapse("haha haha"), "hahahaha")
        // A single already-correct token has nothing to join.
        expect(LaughterSpelling.collapse("haha"), "haha")
        expect(LaughterSpelling.collapse("Haha that's funny"), "Haha that's funny")
    }

    private static func testLeavesALoneSyllableAlone() {
        expect(LaughterSpelling.collapse("ha"), "ha")
        expect(LaughterSpelling.collapse("ha that was funny"), "ha that was funny")
        expect(LaughterSpelling.collapse(""), "")
    }

    /// The word boundaries matter more than the joining does: an ordinary word
    /// that happens to end in "ha" must not be dragged into a run.
    private static func testNeverReachesInsideAnotherWord() {
        expect(LaughterSpelling.collapse("Aloha ha"), "Aloha ha")
        expect(LaughterSpelling.collapse("cha cha"), "cha cha")
        expect(LaughterSpelling.collapse("Martha has it"), "Martha has it")
        expect(LaughterSpelling.collapse("Aloha ha ha"), "Aloha haha")
        expect(LaughterSpelling.collapse("hahn ha"), "hahn ha")
    }

    private static func testNeverJoinsAcrossALineOrSentence() {
        expect(LaughterSpelling.collapse("ha\nha"), "ha\nha")
        expect(LaughterSpelling.collapse("ha. ha"), "ha. ha")
        expect(LaughterSpelling.collapse("ha! ha"), "ha! ha")
        // A run that ends the sentence keeps its punctuation.
        expect(LaughterSpelling.collapse("ha ha!"), "haha!")
        expect(LaughterSpelling.collapse("ha ha."), "haha.")
    }

    private static func testLeavesOrdinaryTextUntouched() {
        let sentence = "Let's ship the build tonight and check the logs in the morning."
        expect(LaughterSpelling.collapse(sentence), sentence)
        expect(LaughterSpelling.collapse("I have a hat"), "I have a hat")
    }

    // MARK: helpers

    private static func expect(_ actual: String, _ expected: String) {
        if actual != expected {
            fatalError("LaughterSpelling: expected \"\(expected)\" but got \"\(actual)\"")
        }
    }
}
