import Foundation

/// Turns spoken punctuation into the mark it names: "thanks exclamation mark"
/// becomes "thanks!", "is that done question mark" becomes "is that done?".
///
/// The cleanup model already does this *sometimes*, which is worse than never
/// doing it. Measured on the shipped pipeline, in both a chat and a terminal
/// context:
///
/// ```
/// thanks exclamation mark                       -> thanks !
/// sounds good exclamation mark let me know question mark
///                                               -> sounds good ! let me know question mark
/// is that done question mark                    -> is that done?
/// ```
///
/// So a trailing "question mark" worked, one in the middle of an utterance was
/// left as literal words, and "exclamation mark" produced a floating " !" with
/// a space in front of it every single time. Deterministic code is the right
/// place for a rule this mechanical — see
/// `deterministic-post-step-beats-prompt-for-precise-rules`.
///
/// Only the two unambiguous marks are handled. "period", "comma", "dash" and
/// "full stop" are ordinary English words ("the Jurassic period", "a comma
/// splice", "dash to the shop", "full stop, no argument") and rewriting them
/// would corrupt real sentences; there is no anchor equivalent to the word
/// "emoji" that `SpokenEmoji` relies on to stay safe.
enum SpokenPunctuation {
    /// Spoken phrase -> mark. Lower case, matched whole-word, longest first so
    /// "exclamation mark" can never be reached as "mark".
    static let marks: [(phrase: [String], mark: Character)] = [
        (["exclamation", "mark"], "!"),
        (["exclamation", "point"], "!"),
        (["question", "mark"], "?"),
    ]

    /// A determiner or possessive in front means the speaker is *talking about*
    /// the mark rather than dictating it: "he asked me to add a question mark
    /// at the end". The shipped model already gets this case right, and this
    /// pass must not break what works.
    private static let nounSignals: Set<String> = [
        "a", "an", "the", "that", "this", "these", "those", "another", "no",
        "any", "one", "each", "every", "some", "its", "his", "her", "their",
        "my", "your", "our", "first", "second", "last", "final", "extra",
        "missing", "trailing", "leading", "double", "single",
    ]

    /// True when the mark should attach to the preceding word. Nothing to
    /// attach to means the phrase opens the text, which is never someone
    /// dictating punctuation.
    private static func isCommand(previous: String?, before: String?) -> Bool {
        guard let previous, !previous.isEmpty else { return false }
        if nounSignals.contains(previous.lowercased()) { return false }
        // "add a trailing question mark" — the determiner is one word further
        // back when an adjective sits between it and the phrase.
        if let before, nounSignals.contains(before.lowercased()),
           nounSignals.contains(previous.lowercased()) { return false }
        return true
    }

    static func substitute(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let lower = text.lowercased()
        // Cheap bail-out: neither word is present, so there is nothing to do.
        guard lower.contains("exclamation") || lower.contains("question") else { return text }

        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var index = 0

        while index < words.count {
            var matched = false
            for (phrase, mark) in marks {
                guard index + phrase.count <= words.count else { continue }
                let candidate = (0..<phrase.count).map { stripped(words[index + $0]).lowercased() }
                guard candidate == phrase else { continue }

                // The word the mark would attach to is the last one kept so far.
                let previous = result.last
                let before = result.count >= 2 ? result[result.count - 2] : nil
                guard isCommand(previous: previous, before: before) else { continue }

                // Attach to the previous word, replacing any punctuation the
                // recogniser put there ("thanks, exclamation mark" -> "thanks!").
                var attached = result.removeLast()
                while let last = attached.last, ",;:.!?".contains(last) { attached.removeLast() }
                guard !attached.isEmpty else { result.append(attached); continue }
                // A trailing bracket or quote keeps the mark inside it.
                result.append(attached + String(mark))

                index += phrase.count
                matched = true
                break
            }
            if !matched {
                result.append(words[index])
                index += 1
            }
        }

        words = result
        return words.joined(separator: " ")
    }

    /// A word without the punctuation the recogniser may have attached, so
    /// "mark," and "mark." still match.
    private static func stripped(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ",;:.!?\"'“”‘’()[]{}"))
    }
}
