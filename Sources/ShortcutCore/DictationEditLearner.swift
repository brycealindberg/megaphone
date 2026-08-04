import Foundation

/// One word the user swapped out after a dictation landed.
struct DictationEditCorrection: Equatable {
    /// What Megaphone inserted.
    let heard: String
    /// What the user replaced it with.
    let written: String
    /// Whether only letter case changed, which is a safe automatic fix; a
    /// respelling is a stronger claim and stays approval-gated.
    let isCaseOnly: Bool
}

/// Learns from post-dictation edits: compares the text Megaphone inserted with
/// the text that is in the field a little later, and reports the single-word
/// substitutions that look like the user fixing a recognition mistake.
///
/// The whole difficulty is telling a *correction* ("get pull" → "git pull") from
/// a *rewrite* ("Thursday" → "Monday", "should" → "must"). A rewrite must never
/// become a dictionary entry, because a wrong entry then biases the recogniser
/// and makes every later dictation worse. So this errs heavily toward silence:
/// a substitution is only reported when the words are close enough to be the
/// same word misheard.
enum DictationEditLearner {
    /// Words that carry no identity — swapping one for another is the user
    /// changing meaning, never fixing a mishearing.
    private static let commonWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can", "did", "do",
        "does", "for", "from", "get", "got", "had", "has", "have", "he", "her", "him", "his",
        "how", "i", "if", "in", "is", "it", "its", "just", "me", "my", "no", "not", "now", "of",
        "on", "one", "or", "our", "out", "she", "so", "than", "that", "the", "their", "them",
        "then", "there", "these", "they", "this", "to", "too", "two", "up", "us", "very", "was",
        "we", "were", "what", "when", "where", "which", "who", "will", "with", "would", "yes",
        "you", "your"
    ]

    /// Maximum corrections taken from a single dictation. A larger diff means
    /// the user rewrote the text rather than fixed a word, so the whole edit is
    /// discarded rather than mined.
    static let maxCorrectionsPerEdit = 3

    /// Longest edit (in words) still treated as a correction pass rather than a
    /// rewrite. Beyond this the alignment is not trustworthy.
    static let maxSubstitutionsBeforeDiscard = 4

    /// Span kept past the end of the dictation, to cover an edit that lengthened
    /// it. Deliberately small — see `window(in:around:)` for why a large tail
    /// corrupts the quality score rather than merely wasting work.
    static let trailingMargin = 120

    /// Span used by the tail fallback, when the dictation cannot be located.
    static let windowMargin = 400

    /// How far back from the end of the field the dictation is looked for. The
    /// text was inserted at the caret moments earlier, so anything beyond this
    /// is not the dictation being harvested.
    static let searchLimit = 20_000

    /// The slice of a focused field worth diffing against one dictation.
    ///
    /// A focused element hands back the app's whole buffer: measured at
    /// 2,053,392 characters in a terminal, where scoring it cost 483 ms and the
    /// correction diff another 327 ms — together about 60% of the time between
    /// the user stopping speaking and the text appearing. The dictation is a few
    /// hundred characters, and `align` refuses anything over 400 words, so the
    /// rest of that buffer could never have produced a correction. It was only
    /// ever paid for.
    ///
    /// Anchors on the start of the inserted text so a dictation edited in the
    /// middle of a long document is still found, and falls back to the tail,
    /// which is where a caret usually sits.
    static func window(in field: String, around inserted: String) -> String {
        // Nothing here may touch the whole buffer. `field.count` is a grapheme
        // walk over every character — 10 ms on 2 MB of real terminal output,
        // where uniform ASCII measures 2.5 ms, so it is content-sensitive and
        // the bad case is the realistic one — and a backwards search is a second
        // pass. Walking back a bounded number of characters is O(k), so cut a
        // tail first and do the work inside that. `utf8.count` is O(1) and is
        // compared against the worst-case bytes-per-character, so the cut only
        // happens when the field is genuinely large.
        let searchable = field.utf8.count > searchLimit * 4
            ? String(field.suffix(searchLimit))
            : field
        // Gate on the same tail the anchor branch keeps, not on the fallback's
        // generous one: otherwise a merely medium-sized field skips windowing
        // altogether and keeps all its trailing prose, which is the case the
        // trailing margin exists to bound.
        guard searchable.count > inserted.count + trailingMargin else { return searchable }
        let anchor = String(inserted.prefix(24))
        if !anchor.isEmpty,
           let found = searchable.range(of: anchor, options: [.backwards]) {
            // Starts exactly at the dictation, and keeps only a small tail.
            //
            // Surrounding prose is not context here, it is noise: `align` pairs a
            // dropped word with whatever follows it, so text after the dictation
            // gets mis-paired against dictation words and every mis-pair counts
            // as a deletion. With a 400-character tail, a mid-document dictation
            // the user never touched scored 0.917 — reported as *measured*, and
            // biased downward, which is exactly the direction that makes a
            // harmless prompt change look like a regression.
            //
            // The tail still has to cover an edit that lengthened the text
            // ("git" -> "GitHub"), which is tens of characters, not hundreds.
            let start = found.lowerBound
            let end = searchable.index(found.lowerBound, offsetBy: inserted.count + trailingMargin, limitedBy: searchable.endIndex)
                ?? searchable.endIndex
            return String(searchable[start..<end])
        }
        // Anchor not found — the opening was edited past recognition. Take a
        // generous tail, since there is no longer anything saying where in it
        // the dictation sits.
        return String(searchable.suffix(inserted.count + windowMargin))
    }

    static func corrections(inserted: String, edited: String) -> [DictationEditCorrection] {
        let before = words(in: inserted)
        let after = words(in: edited)
        guard !before.isEmpty, !after.isEmpty else { return [] }

        // A field can hold far more than this dictation (the user's earlier
        // paragraphs). Align only against the window that plausibly contains it.
        let substitutions = alignedSubstitutions(before, after)

        // Too many changes: this is a rewrite. Learning from it would poison
        // the dictionary, so take nothing at all.
        guard !substitutions.isEmpty, substitutions.count <= maxSubstitutionsBeforeDiscard else {
            return []
        }

        var result: [DictationEditCorrection] = []
        for (heard, written) in substitutions {
            guard let correction = classify(heard: heard, written: written) else { continue }
            result.append(correction)
            if result.count == maxCorrectionsPerEdit { break }
        }
        return result
    }

    /// Decides whether a single word swap is a recognition fix worth learning.
    static func classify(heard: String, written: String) -> DictationEditCorrection? {
        let h = heard.trimmingCharacters(in: punctuation)
        let w = written.trimmingCharacters(in: punctuation)
        guard !h.isEmpty, !w.isEmpty, h != w else { return nil }
        guard w.count >= 2, h.count >= 2, w.count <= 40 else { return nil }
        // Numbers are dictated in many valid forms ("22" vs "twenty-two"); a
        // swap between them is a formatting preference, not a vocabulary fact.
        guard !w.contains(where: \.isNumber) || !h.contains(where: \.isNumber) else { return nil }

        let hl = h.lowercased()
        let wl = w.lowercased()

        // Case-only: the same word, differently capitalised. Safe and common
        // ("claude" -> "Claude").
        if hl == wl { return DictationEditCorrection(heard: h, written: w, isCaseOnly: true) }

        // Two ordinary words swapped is a meaning change, not a mishearing.
        if commonWords.contains(hl) && commonWords.contains(wl) { return nil }

        // One word being the start of the other means the user changed an
        // ending, not the word: "branch" -> "branches", "deploy" -> "deployed",
        // "run" -> "running". That is grammar, and putting an inflected form in
        // the dictionary teaches the recogniser nothing it did not know.
        // Measured against live TextEdit: this was the one false positive the
        // end-to-end run produced.
        if hl.hasPrefix(wl) || wl.hasPrefix(hl) { return nil }

        // The corrected word must be a plausible mishearing of what was heard.
        guard soundsLikeSameWord(hl, wl) else { return nil }
        return DictationEditCorrection(heard: h, written: w, isCaseOnly: false)
    }

    // MARK: - similarity

    /// Close enough that one is credibly a misrecognition of the other. Length
    /// is the scale: short words get an absolute budget of 1 edit, longer words
    /// up to a third of their length.
    static func soundsLikeSameWord(_ a: String, _ b: String) -> Bool {
        let shorter = min(a.count, b.count)
        let longer = max(a.count, b.count)
        // "git"/"deploy" are not the same word however you squint.
        guard longer - shorter <= max(2, shorter / 2) else { return false }
        // ceil(shorter/3), min 1: 3->1 (git/get), 5->2 (cloud/Claude), 9->3.
        // A looser budget only costs recall of benign false positives — a real
        // word the user typed, added as an approval-gated suggestion — never a
        // wrong heard->written mapping.
        let budget = max(1, (shorter + 2) / 3)
        return levenshtein(Array(a), Array(b), limit: budget) <= budget
    }

    /// Standard edit distance, abandoned early once it exceeds `limit` so a
    /// long mismatch costs almost nothing.
    static func levenshtein(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowBest = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: - alignment

    private static let punctuation = CharacterSet(charactersIn: ".,;:!?\"'“”‘’()[]{}…")

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// A word-level alignment of `before` onto `after`.
    struct Alignment {
        /// One-for-one replacements, including recapitalisations.
        let substitutions: [(String, String)]
        /// Words of `before` that nothing in `after` corresponds to.
        ///
        /// Insertions have no equivalent here on purpose: `after` may be an
        /// entire document, so every word of it that is not part of this
        /// dictation would count as one. `before` is always bounded, so a drop
        /// out of it is a real signal and an add into `after` is not.
        let deletions: [String]
    }

    /// Word-level diff via longest common subsequence. Returns nil when the
    /// input is too large to align, which is not the same as "nothing changed"
    /// — callers that report a number must say "unmeasured" rather than
    /// reporting a perfect score they did not compute.
    static func align(_ before: [String], _ after: [String]) -> Alignment? {
        // Guard against pathological inputs; a field can contain a whole document.
        guard before.count <= 400, after.count <= 400 else { return nil }

        let key: (String) -> String = { $0.lowercased().trimmingCharacters(in: punctuation) }
        let n = before.count, m = after.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = key(before[i]) == key(after[j])
                    ? lcs[i + 1][j + 1] + 1
                    : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var result: [(String, String)] = []
        var dropped: [String] = []
        var i = 0, j = 0
        while i < n && j < m {
            if key(before[i]) == key(after[j]) {
                // Same word, but possibly recapitalised — that is a real signal.
                if before[i] != after[j] { result.append((before[i], after[j])) }
                i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                // before[i] was dropped. A 1:1 replacement shows up as a drop
                // immediately followed by an add, so pair them up here.
                if j < m, lcs[i + 1][j] == lcs[i][j + 1] {
                    result.append((before[i], after[j]))
                    i += 1; j += 1
                } else {
                    dropped.append(before[i])
                    i += 1
                }
            } else {
                j += 1
            }
        }
        // Whatever is left of `before` ran off the end of `after` — a truncated
        // result is the largest drop there is, and the loop above exits without
        // ever seeing it.
        if i < n { dropped.append(contentsOf: before[i..<n]) }
        return Alignment(substitutions: result, deletions: dropped)
    }

    /// The replacements alone. Added or removed words are the user writing
    /// rather than correcting, so the edit learner never learns from them.
    static func alignedSubstitutions(_ before: [String], _ after: [String]) -> [(String, String)] {
        align(before, after)?.substitutions ?? []
    }
}
