import Foundation

/// Rewrites a misheard name to the spelling that is visible on screen.
///
/// This exists because neither of the two obvious routes works. Measured on
/// macOS 26.5:
///
///   * `AnalysisContext.contextualStrings` has no observable effect on
///     `SpeechTranscriber`. `setContext` succeeds and reads back, and the
///     transcript is byte-identical with the name supplied 20 times over.
///   * Telling the cleanup model the correct spellings does not fix it either
///     (0/9). It sometimes deletes the word it cannot place instead.
///
/// So the repair is deterministic, matching how `word_corrections` already has
/// to be re-applied to the model's output rather than merely described to it.
///
/// The bar for a replacement is deliberately high: a name is only rewritten
/// when it is a near miss for something actually on screen, because a false
/// positive corrupts words the speaker really did say.
enum SpokenNameRepair {
    /// Widest span of transcript words considered for one screen name. A name
    /// heard as separate words ("Ledger IQ", "a Conquo") needs more slots than
    /// the name itself has.
    private static let extraWindowWords = 1
    private static let minimumNameLength = 5

    /// - Parameters:
    ///   - names: spellings visible on screen, from `ScreenVocabulary`.
    ///   - protected: words the user's own dictionary already fixes. Never
    ///     overwritten — an explicit term outranks anything read off a window.
    static func apply(_ text: String, names: [String], protected: [String] = []) -> String {
        guard !text.isEmpty, !names.isEmpty else { return text }
        let blocked = Set(protected.map(normalize))
        var result = text

        // Longest first: "Marek Vasiliev" should win before "Marek" gets a turn.
        for rawName in names.sorted(by: { $0.count > $1.count }) {
            let name = droppingPossessive(rawName)
            guard name.count >= minimumNameLength else { continue }
            let normalizedName = normalize(name)
            guard !normalizedName.isEmpty, !blocked.contains(normalizedName) else { continue }
            // Already spelled correctly somewhere: nothing to repair.
            if result.range(of: name, options: [.caseInsensitive]) != nil { continue }
            result = replacingBestMatch(in: result, with: name)
        }
        return result
    }

    /// A screen name is only ever a *spelling*. A possessive is grammar, and it
    /// belongs to the sentence the speaker actually said — so "Merrick's" on
    /// screen contributes the target "Merrick", never the possessive itself.
    ///
    /// Without this the repair rewrites correctly-heard names, because a
    /// trailing "'s" is exactly one edit away and the capitalisation guard is
    /// powerless here: both forms are proper nouns, so the rule that stops
    /// ordinary words becoming names cannot see this at all. Two of twenty
    /// consecutive real dictations were corrupted before it was caught;
    /// reproduced against the shipped code as —
    ///
    ///     "send Merrick an update"      -> "send Merrick's an update"
    ///     "Trelawney is here today"     -> "Trelawney's here today"
    ///     "Okonkwo said she would come" -> "Okonkwo's said she would come"
    ///
    /// Only an apostrophe form is stripped, so ordinary names that simply end
    /// in s ("Travis", "Jones", "Rogers") are untouched. The reverse direction
    /// never needed a guard: a screen "Marek" against a spoken "Marek's"
    /// already short-circuits on the substring check above.
    private static func droppingPossessive(_ name: String) -> String {
        for suffix in ["'s", "\u{2019}s", "'S", "\u{2019}S"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    // MARK: Matching

    private static func replacingBestMatch(in text: String, with name: String) -> String {
        let words = tokenize(text)
        guard !words.isEmpty else { return text }
        let nameWords = name.split(separator: " ").count
        let maxSpan = nameWords + extraWindowWords

        var best: (range: Range<String.Index>, score: Int)?
        for start in words.indices {
            for span in 1...maxSpan where start + span <= words.count {
                let window = words[start..<(start + span)]
                guard let lower = window.first?.range.lowerBound,
                      let upper = window.last?.range.upperBound else { continue }
                // The recogniser capitalises what it believes is a name, and
                // that signal is what keeps this pass safe: measured, every
                // false positive found ("the marks are in" -> "the marcus are
                // in", "I read the manual twice" -> "the manuel") was a
                // lowercase ordinary word. Repair only what was already
                // written as a proper noun.
                guard window.first?.text.first?.isUppercase == true else { continue }
                let candidate = window.map(\.text).joined(separator: " ")
                guard let score = matchScore(candidate: candidate, name: name) else { continue }
                if best == nil || score < best!.score {
                    best = (lower..<upper, score)
                }
            }
        }

        guard let best else { return text }
        var result = text
        result.replaceSubrange(best.range, with: name)
        return result
    }

    /// Lower is better; `nil` means "not a match, leave it alone".
    ///
    /// Two independent tests must both pass. The consonant skeleton catches a
    /// name heard as a different vowel set ("Merrick" for "Marek"), and the
    /// edit distance stops the skeleton from being generous — without it,
    /// every short skeleton collides with something.
    private static func matchScore(candidate: String, name: String) -> Int? {
        let a = normalize(candidate)
        let b = normalize(name)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        if a == b { return 0 }
        // A wildly different length is a different word, whatever it sounds like.
        guard abs(a.count - b.count) <= 3 else { return nil }

        let skeletonDistance = editDistance(skeleton(a), skeleton(b))
        let rawDistance = editDistance(a, b)

        // The candidate is already known to be a proper noun, so an identical
        // consonant skeleton can carry a budget that scales with the name:
        // "Merrick" for "Marek" is three edits on five letters, and "Dana a
        // Conquo" for "Dana Okonkwo" is four over eleven. A skeleton that is
        // merely close stays on a much tighter leash.
        if skeletonDistance == 0, rawDistance <= max(3, (b.count * 3) / 5) { return rawDistance }
        if skeletonDistance == 1, rawDistance <= max(1, b.count / 4) { return rawDistance + 2 }
        return nil
    }

    /// Consonant skeleton: vowels dropped, like-sounding consonants merged,
    /// runs collapsed. "merrick" and "marek" both reduce to "mrk".
    private static func skeleton(_ normalized: String) -> String {
        var out = ""
        for character in normalized {
            let mapped: Character?
            switch character {
            case "a", "e", "i", "o", "u", "y", "h", "w": mapped = nil
            case "c", "k", "q", "g", "x": mapped = "k"
            case "s", "z": mapped = "s"
            case "f", "v": mapped = "f"
            case "d", "t": mapped = "t"
            case "b", "p": mapped = "p"
            case "m", "n": mapped = "n"
            default: mapped = character
            }
            if let mapped, out.last != mapped { out.append(mapped) }
        }
        return out
    }

    /// Doubled letters are collapsed so a distance reflects how differently a
    /// name was *heard*, not how it happens to be spelled: without this,
    /// "merrick" sits four edits from "marek" purely on the doubled r.
    private static func normalize(_ value: some StringProtocol) -> String {
        var out = ""
        for character in value.lowercased() where character.isLetter || character.isNumber {
            if out.last != character { out.append(character) }
        }
        return out
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        let a = Array(lhs), b = Array(rhs)
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

    // MARK: Text handling

    private struct Word { let text: String; let range: Range<String.Index> }

    private static func tokenize(_ text: String) -> [Word] {
        var words: [Word] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, text[index].isLetter || text[index].isNumber {
                index = text.index(after: index)
            }
            words.append(Word(text: String(text[start..<index]), range: start..<index))
        }
        return words
    }

}
