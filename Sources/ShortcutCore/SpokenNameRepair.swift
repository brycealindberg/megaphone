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
    /// Shortest consonant skeleton that can carry a match. See `matchScore`.
    private static let minimumSkeletonLength = 3

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
                // A capital is only the recogniser's opinion when grammar has
                // not already forced one. Every sentence opens with a capital
                // and the pronoun "I" carries one wherever it falls, so on its
                // own the guard above waves ordinary words through at the two
                // positions dictation produces most. Measured over the eleven
                // days to 2026-08-18: 45 of 3,565 real dictations had a word
                // the speaker said correctly swapped for a screen term —
                // "I can do Monday" -> "Queen do Monday", "I'll follow up" ->
                // "Hello follow up", "Did the messages" -> "Added the
                // messages" — and seventeen of them were sent to people.
                //
                // Every window word is checked, not just the first: a name
                // that correctly matched can otherwise drag the next word in
                // with it ("Priya was texting" -> "Priya Sam texting").
                guard !window.contains(where: { isOrdinaryWord($0.text) }) else { continue }
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

    /// Common English, which a screen term may never overwrite however alike
    /// the two sound.
    ///
    /// `SentenceContinuation.functionWords` is the same judgement already made
    /// once — "words that are never proper nouns" — so it is reused rather than
    /// restated. Two adjustments, both for reasons that belong to this pass:
    ///
    ///   * **"i" is added.** That list leaves it out deliberately, because it
    ///     decides what to *lowercase* and the pronoun must keep its capital.
    ///     Here the question is the opposite one — whether a capital means
    ///     anything — and for "I" it never does.
    ///   * **"a" is removed.** It is how the recogniser renders a name it could
    ///     not place ("Dana a Conquo" for "Dana Okonkwo"), so inside a window it
    ///     is part of the mishear rather than a word the speaker chose. It can
    ///     only ever be consumed mid-window: the uppercase guard stops a
    ///     lowercase article from starting one.
    ///
    /// The interjections are local because that list has no need of them, and
    /// they earn their place: an interjection opens a sentence, so it collects
    /// a capital, and it is exactly the kind of short word whose skeleton lands
    /// near something. "Dang" was the largest false positive left after the
    /// skeleton floor, turning into a screen term reading "Waiting" five times.
    private static let ordinaryWords: Set<String> = SentenceContinuation.functionWords
        .union([
            "i", "oh", "ok", "yes", "hey", "hi", "um", "uh", "sure", "wait",
            "dang", "damn", "wow", "huh", "nah", "aha", "lol", "lmao", "yikes",
            "bro", "dude", "man",
        ])
        .subtracting(["a"])

    /// Apostrophes do not survive `tokenize`, so "I'll" arrives as "I" + "ll"
    /// and matching the stem is enough to catch the whole contraction.
    private static func isOrdinaryWord(_ word: String) -> Bool {
        ordinaryWords.contains(word.lowercased())
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

        let candidateSkeleton = skeleton(a)
        let nameSkeleton = skeleton(b)
        // A skeleton this short is not an acoustic fingerprint, it is a
        // coincidence waiting to happen — and because vowels drop out entirely
        // it can even come back empty, at which point two words match on
        // nothing at all. Measured by replaying 3,565 real dictations: "AI" and
        // "UI" and a bare "A" (all skeleton "") matched a screen term reading
        // "YOOOO", "AWS" and "AZ" (skeleton "s") both matched "a-zA-Z", and an
        // ordinary given name whose skeleton is a single "l" became a button
        // reading "Hello". Acronyms are the common shape here, since dropping
        // vowels is most of what makes one.
        //
        // Three is the floor every measured true repair clears with room spare
        // — Marek "nrk", Okonkwo "knk", LedgerIQ "ltkrk", Travis "trfs".
        //
        // The floor is checked before the equality shortcut below, not after:
        // `normalize` collapses doubled letters, so "Yo" and a screen term
        // reading "YOOOO" arrive here as the same string and would otherwise
        // match perfectly.
        guard candidateSkeleton.count >= minimumSkeletonLength,
              nameSkeleton.count >= minimumSkeletonLength else { return nil }

        if a == b { return 0 }
        // A wildly different length is a different word, whatever it sounds like.
        guard abs(a.count - b.count) <= 3 else { return nil }

        let skeletonDistance = editDistance(candidateSkeleton, nameSkeleton)
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
