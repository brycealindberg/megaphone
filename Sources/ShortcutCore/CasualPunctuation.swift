import Foundation

/// Trims the commas the cleanup model sprinkles into casual chat, so a dictated
/// "okay bet I will" is written "Okay bet I will" and not "Okay, bet I will".
///
/// Only ever removes commas. It cannot touch capitalization, question marks, or
/// any other punctuation — which is the whole reason it is deterministic code
/// and not a line in the cleanup prompt. Every prompt wording that suppressed
/// these commas also made the small on-device model drop question marks and
/// capitals; a pass that only sees commas cannot make that mistake.
///
/// Scope is deliberately narrow. It runs only in the casual-chat context, and
/// it protects number commas ("1,000") and multi-comma lists ("eggs, milk, and
/// bread"), because those carry meaning even in a text message.
enum CasualPunctuation {
    /// Discourse markers and interjections that never need a trailing comma when
    /// they open a casual message. Matched only at the very start.
    /// Multi-word entries must come before their single-word prefixes so the
    /// longer match wins ("no worries" before "no").
    static let leadingOpeners: [String] = [
        "no worries", "for sure", "for real", "my bad", "i mean", "you know",
        "okay", "ok", "kk", "yeah", "yea", "yep", "yup", "nah", "nope", "no",
        "haha", "hah", "lol", "lmao", "lmfao", "hey", "hi", "hello", "yo",
        "oh", "ah", "aww", "aw", "well", "so", "bet", "word", "aight", "ight",
        "alright", "sure", "damn", "dang", "omg", "oof", "hmm", "hm", "wait",
        "fr", "ngl", "tbh", "anyways", "anyway", "cool", "nice", "bruh",
        "bro", "dude", "man", "sheesh", "yikes",
        // Added 2026-08-05 after Bryce dictated a comma test whose leading
        // "Also," survived. Measured over the 120 real-voice cases: 3 more
        // commas removed, all 3 agreeing with his own edits, no new false
        // positives — precision 92.3% -> 92.6%.
        "also"
    ]

    /// Longest message (in words) still treated as a short chat line, where a
    /// single stray clause comma is dropped. Above this, a lone comma is more
    /// likely to be doing real work, so it is left alone.
    static let maxShortMessageWords = 10

    /// Politeness particles that get a spoken pause in front of them, which the
    /// recogniser writes as a comma and Bryce then deletes. `, please` was the
    /// single most common unwanted comma in the corpus — 17 occurrences, more
    /// than twice any other context.
    static let politenessParticles = ["please", "though", "as well"]

    static func lighten(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = stripLeadingOpenerComma(text)
        result = stripShortMessageCommas(result)
        result = stripPolitenessCommas(result)
        return result
    }

    // MARK: - leading opener

    /// "Okay, bet I will" -> "Okay bet I will". Removes exactly the comma that
    /// sits right after a leading interjection, preserving its original case.
    static func stripLeadingOpenerComma(_ text: String) -> String {
        let alternation = leadingOpeners
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s+"#) }
            .joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            // start, optional space, an opener, optional space, the comma.
            pattern: #"^(\s*)(?:"# + alternation + #")(\s*),"#,
            options: [.caseInsensitive]
        ) else { return text }

        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range) else { return text }
        // Drop only the trailing comma (the last character of the whole match).
        let commaIndex = match.range.location + match.range.length - 1
        let mutable = NSMutableString(string: text)
        mutable.deleteCharacters(in: NSRange(location: commaIndex, length: 1))
        return collapseSpaces(mutable as String)
    }

    // MARK: - lone clause comma

    /// A short chat line reads better without its clause/interjection commas
    /// ("no worries man, all good", "yeah man, for sure, let's link up"). Strips
    /// every non-numeric comma, except in an actual list, which keeps its commas.
    /// Number commas ("1,000") are always kept.
    ///
    /// Two signals mark a real list, both requiring two or more commas:
    ///   - a coordinating "and"/"or"/"nor" — "milk, eggs, and bread"
    ///   - a colon before the first comma, which introduces an enumeration —
    ///     "three things: the dictionary, the sounds, the double tap"
    ///
    /// The colon signal exists because a dictated list often has no "and", and
    /// without it every comma was stripped: that exact sentence came out as
    /// "Three things: the dictionary the sounds the double tap". A colon cannot
    /// reintroduce the stacked-discourse case it has to stay away from, because
    /// those never contain one.
    static func stripShortMessageCommas(_ text: String) -> String {
        let wordCount = text.split { $0 == " " || $0.isNewline }.count
        guard wordCount <= maxShortMessageWords else { return text }

        // Commas that are not between two digits — i.e. not "1,000".
        guard let regex = try? NSRegularExpression(pattern: #"(?<![0-9]),(?![0-9])"#) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        // Leave a genuine list intact: a coordinating conjunction alongside two
        // or more commas is "A, B, and C", not stacked discourse commas.
        if matches.count >= 2,
           text.range(of: #"\b(and|or|nor)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return text
        }

        // Or a colon that introduces the enumeration. It must come before the
        // first comma to be a lead-in; a colon later in the line is doing
        // something else and does not protect the commas ahead of it.
        if matches.count >= 2 {
            let colon = ns.range(of: ":")
            if colon.location != NSNotFound, colon.location < matches[0].range.location {
                return text
            }
        }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.deleteCharacters(in: match.range)
        }
        return collapseSpaces(mutable as String)
    }

    // MARK: - politeness particles

    /// "Let me know, please" -> "Let me know please". Unlike the rule above this
    /// is not length-gated, because a trailing "please" reads the same in a long
    /// sentence as a short one, and the length gate is exactly why Bryce's own
    /// 15-word comma test came back unchanged.
    ///
    /// Measured over the 120 real-voice cases, on top of the opener and
    /// short-message rules: 20 more commas removed, 16 of them agreeing with his
    /// edits and 4 not — 101 removed at 90.1% precision, against 81 at 92.6%
    /// without it. Kept because the 4 are commas he sometimes writes either way,
    /// while the 16 are ones he consistently deletes.
    ///
    /// Cannot touch a number ("1,000 please" has no comma directly before the
    /// word) and cannot remove anything but a comma.
    static func stripPolitenessCommas(_ text: String) -> String {
        let alternation = politenessParticles
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s+"#) }
            .joined(separator: "|")
        let pattern = #"\s*,\s*(?=(?:"# + alternation + #")(?![\p{L}\p{N}]))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let ns = NSMutableString(string: text)
        regex.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return collapseSpaces(ns as String)
    }

    // MARK: - helpers

    private static func collapseSpaces(_ text: String) -> String {
        // Removing a comma can leave a double space or a leading space.
        let collapsed = text.replacingOccurrences(
            of: #"[ \t]{2,}"#, with: " ", options: .regularExpression
        )
        return collapsed.replacingOccurrences(
            of: #" +([.!?;:])"#, with: "$1", options: .regularExpression
        )
    }
}
