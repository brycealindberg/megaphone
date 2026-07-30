import Foundation

/// Adds a question mark to an obvious question the cleanup model left flat —
/// "can you send that over" becomes "can you send that over?". The on-device
/// model does this inconsistently (measured: ~half of clear questions came back
/// with no "?"), and Wispr Flow, which hears the rising intonation, always gets
/// them.
///
/// Only ever *adds* a "?" (or upgrades a trailing "." to "?") to the final
/// sentence, and only when that sentence is unmistakably a question from its
/// wording alone. It cannot remove or alter any other punctuation — the whole
/// reason it is deterministic code, not a line in the cleanup prompt, where
/// every wording that touched question marks also broke them.
///
/// It deliberately fires only on text-evident questions: a wh-word, an auxiliary
/// followed by a subject ("can you", "is this", "did we"), "wanna", or a casual
/// "you …ing / you free" tag. Statements that are questions by tone alone
/// ("you forgot the keys?") are left flat, because nothing in the text says so —
/// that is the one thing an audio model can do that this cannot.
enum QuestionMark {
    private static let whWords: Set<String> = [
        "what", "when", "where", "who", "whom", "whose", "which", "why", "how"
    ]
    /// Auxiliaries/modals. At the start of a sentence, followed by a subject,
    /// these open a question. Requiring the subject excludes imperatives
    /// ("do the dishes", "have a seat") and name collisions ("Will is here").
    private static let auxiliaries: Set<String> = [
        "do", "does", "did", "is", "are", "am", "was", "were", "can", "could",
        "will", "would", "shall", "should", "may", "might", "must", "have", "has", "had"
    ]
    private static let subjects: Set<String> = [
        "you", "we", "i", "he", "she", "it", "they", "u", "ya",
        "this", "that", "these", "those", "there"
    ]
    /// Casual "you …" tag questions: "you free?", "you around?", "you good?".
    /// Paired with a gerund check ("you coming", "you working late").
    private static let tagPredicates: Set<String> = [
        "free", "up", "around", "down", "good", "busy", "home", "ready", "sure",
        "in", "out", "available", "there", "ok", "okay", "cool", "still", "done", "close"
    ]

    static func punctuate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        // Respect an existing terminal ? or ! — never override the model there.
        if let last = trimmed.last, last == "?" || last == "!" { return text }

        // Drop the sentence's own trailing "." first, so it does not read as a
        // sentence boundary and leave us scanning an empty last sentence. A
        // question closed with a period is thereby upgraded, not left as "…?.".
        var body = trimmed
        if body.hasSuffix(".") { body.removeLast() }
        body = body.trimmingCharacters(in: .whitespaces)

        let ns = body as NSString
        let sentenceStart = lastSentenceStart(in: ns)
        let sentence = ns.substring(from: sentenceStart)
            .trimmingCharacters(in: .whitespaces)

        guard looksLikeQuestion(sentence) else { return text }

        let prefix = ns.substring(to: sentenceStart)
        return prefix + sentence + "?"
    }

    static func looksLikeQuestion(_ sentence: String) -> Bool {
        let stripped = sentence.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'“”‘’([{ \t")
        )
        let words = stripped.split { $0 == " " || $0.isNewline }.map(String.init)
        guard let rawFirst = words.first else { return false }
        let w0 = rawFirst.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:'"))
        let w1 = words.count > 1
            ? words[1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:'"))
            : ""

        // wh-question, but not an instructional infinitive ("how to reset …").
        if whWords.contains(w0) { return w1 != "to" }
        // auxiliary + subject ("can you", "is this", "did we").
        if auxiliaries.contains(w0), subjects.contains(w1) { return true }
        // "wanna grab dinner" == "(do you) wanna grab dinner".
        if w0 == "wanna" { return true }
        // casual "you …" tag: "you free", "you coming", "you working late".
        if w0 == "you" || w0 == "u" || w0 == "ya" {
            if tagPredicates.contains(w1) { return true }
            if w1.hasSuffix("ing"), w1.count > 3 { return true }
        }
        return false
    }

    /// Index just after the previous sentence terminator (. ! ? / newline).
    private static func lastSentenceStart(in ns: NSString) -> Int {
        var i = ns.length - 1
        while i >= 0 {
            if let s = UnicodeScalar(ns.character(at: i)),
               s == "." || s == "!" || s == "?" || s == "\n" {
                var start = i + 1
                while start < ns.length,
                      let sp = UnicodeScalar(ns.character(at: start)),
                      CharacterSet.whitespaces.contains(sp) {
                    start += 1
                }
                return start
            }
            i -= 1
        }
        return 0
    }
}
