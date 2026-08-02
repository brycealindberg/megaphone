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
        /// False when the text was too large to align. The score is then not a
        /// measurement and must not be logged as one — before this existed, any
        /// dictation into a document over 400 words silently reported 1.000.
        let isMeasured: Bool
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
        guard !a.isEmpty else { return Score(accuracy: 1, changedWords: 0, totalWords: 0, isMeasured: true) }
        let b = DictationEditLearner.words(in: edited).filter(isWord)
        guard !b.isEmpty else { return Score(accuracy: 0, changedWords: a.count, totalWords: a.count, isMeasured: true) }

        // The field holds far more than this dictation — in a document it is the
        // whole document. Comparing against all of it scored every real
        // dictation 0.000, which is what the first live run reported. Reuse the
        // alignment the edit learner already does for exactly this reason.
        guard let alignment = DictationEditLearner.align(a, b) else {
            return Score(accuracy: 1, changedWords: 0, totalWords: a.count, isMeasured: false)
        }

        // Only substantive swaps count. The alignment also surfaces case- and
        // punctuation-only pairs ("ship" -> "Ship"), which the edit learner
        // wants but a word-accuracy score does not: this measures whether the
        // right words were heard, not how they were formatted.
        let substantive = alignment.substitutions.filter { heard, written in
            normalizedWord(heard) != normalizedWord(written)
        }
        // Deletions are counted too, and they are why this line exists. Scoring
        // substitutions alone let a word be *removed* for free, which is exactly
        // the failure mode a shorter cleanup prompt introduces: measured over
        // 120 real dictations, trimming the prompt cost 19 extra dropped words
        // and 0 extra substitutions, so a substitution-only score called it a
        // dead heat (-0.0003) while true word accuracy was -0.0125.
        //
        // Insertions stay uncounted — `edited` may be a whole document, so every
        // word of it outside this dictation would score as one.
        let changed = min(substantive.count + alignment.deletions.count, a.count)
        return Score(
            accuracy: max(0, 1 - Double(changed) / Double(a.count)),
            changedWords: changed,
            totalWords: a.count,
            isMeasured: true
        )
    }

}
