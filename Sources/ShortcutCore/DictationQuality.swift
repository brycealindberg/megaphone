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

    static func score(inserted: String, edited: String) -> Score {
        let a = words(inserted)
        let b = words(edited)
        guard !a.isEmpty else { return Score(accuracy: 1, changedWords: 0, totalWords: 0) }
        let distance = wordDistance(a, b)
        let changed = min(distance, a.count)
        return Score(
            accuracy: max(0, 1 - Double(distance) / Double(a.count)),
            changedWords: changed,
            totalWords: a.count
        )
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}") }
            .map(String.init)
    }

    private static func wordDistance(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
