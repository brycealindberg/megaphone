import Foundation

/// Written laughter is one word. Speech recognition hears the syllables and
/// writes them apart — "ha ha ha" — so a run of adjacent laughter syllables is
/// joined back into "hahaha".
///
/// The pass only ever *deletes the separators between two laughter tokens*. It
/// cannot introduce a word, change a letter, or reach any token that is not
/// built purely from repeated "ha". That is why it runs unconditionally rather
/// than behind a profile switch: there is no destination app where "ha ha" is
/// meant to stay apart. Exact mode never reaches it — that path returns the
/// verbatim transcript before any finishing step runs.
enum LaughterSpelling {
    /// Matches two or more laughter tokens in a row. A token is any repetition
    /// of "ha" ("ha", "haha"), so "haha ha" joins as readily as "ha ha".
    ///
    /// The separator is a space or a comma — the cleanup model likes to write
    /// "Ha, ha" — but never a newline or sentence punctuation, so laughter at
    /// the end of one line is never pulled onto the next.
    private static let pattern = #"""
    (?<![\p{L}\p{M}\p{N}_])(?:ha)+(?:(?:[ \t]*,[ \t]*|[ \t]+)(?:ha)+)+(?![\p{L}\p{M}\p{N}_])
    """#

    static func collapse(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let heard = ns.substring(with: match.range)
            result.replaceCharacters(in: match.range, with: joined(heard))
        }
        return result as String
    }

    /// Rebuilds a matched run as one word, keeping the case the speaker's text
    /// already had: "HA HA" stays a shout, "Ha ha" keeps its sentence capital,
    /// and anything else is plain lower case.
    private static func joined(_ heard: String) -> String {
        let letters = heard.filter { $0.isLetter }
        let syllables = letters.count / 2
        guard syllables >= 2 else { return heard }

        if letters == letters.uppercased() {
            return String(repeating: "HA", count: syllables)
        }
        if letters.first?.isUppercase == true {
            return "Ha" + String(repeating: "ha", count: syllables - 1)
        }
        return String(repeating: "ha", count: syllables)
    }
}
