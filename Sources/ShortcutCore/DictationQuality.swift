import Foundation

/// How close the text Megaphone inserted was to the text the user ended up with.
///
/// This exists because there was no number at all: every claim that a change
/// "improved dictation" was unfalsifiable. The read-back that powers
/// `DictationEditLearner` already knows both strings 25s after insertion, so the
/// measurement is free — it just was not being taken.
///
/// Word-level, not character-level, because a one-letter fix in a long word and
/// a whole wrong word are not the same defect.
enum DictationQuality {
    struct Score {
        let accuracy: Double     // 1.0 = untouched
        let changedWords: Int
        let totalWords: Int
    }

    private static func isWord(_ token: String) -> Bool {
        token.contains { $0.isLetter || $0.isNumber }
    }

    private static func normalizedWord(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func score(inserted: String, edited: String) -> Score {
        // Whitespace tokens that carry no letter or digit are punctuation, not
        // words, and must not dilute the count in either direction.
        let a = DictationEditLearner.words(in: inserted).filter(isWord)
        guard !a.isEmpty else { return Score(accuracy: 1, changedWords: 0, totalWords: 0) }
        let b = DictationEditLearner.words(in: edited).filter(isWord)
        guard !b.isEmpty else { return Score(accuracy: 0, changedWords: a.count, totalWords: a.count) }

        // The field holds far more than this dictation — in a document it is the
        // whole document. Comparing against all of it scored every real
        // dictation 0.000, which is what the first live run reported. Reuse the
        // alignment the edit learner already does for exactly this reason.
        // Only substantive swaps count. The alignment also surfaces case- and
        // punctuation-only pairs ("ship" -> "Ship"), which the edit learner
        // wants but a word-accuracy score does not: this measures whether the
        // right words were heard, not how they were formatted.
        let substantive = DictationEditLearner.alignedSubstitutions(a, b).filter { heard, written in
            normalizedWord(heard) != normalizedWord(written)
        }
        let changed = min(substantive.count, a.count)
        return Score(
            accuracy: max(0, 1 - Double(changed) / Double(a.count)),
            changedWords: changed,
            totalWords: a.count
        )
    }

}
