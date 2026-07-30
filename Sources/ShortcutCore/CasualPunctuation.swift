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
        "bro", "dude", "man", "sheesh", "yikes"
    ]

    /// Longest message (in words) still treated as a short chat line, where a
    /// single stray clause comma is dropped. Above this, a lone comma is more
    /// likely to be doing real work, so it is left alone.
    static let maxShortMessageWords = 10

    static func lighten(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = stripLeadingOpenerComma(text)
        result = stripLoneShortClauseComma(result)
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

    /// A short chat line with a single, non-numeric comma ("no worries man, all
    /// good") reads better in casual chat without it. Multi-comma lists and
    /// number commas are left untouched.
    static func stripLoneShortClauseComma(_ text: String) -> String {
        let wordCount = text.split { $0 == " " || $0.isNewline }.count
        guard wordCount <= maxShortMessageWords else { return text }

        // Commas that are not between two digits — i.e. not "1,000".
        guard let regex = try? NSRegularExpression(pattern: #"(?<![0-9]),(?![0-9])"#) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count == 1 else { return text }

        let mutable = NSMutableString(string: text)
        mutable.deleteCharacters(in: matches[0].range)
        return collapseSpaces(mutable as String)
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
