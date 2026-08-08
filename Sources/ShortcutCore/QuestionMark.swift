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
    /// Bare auxiliaries that are also imperative verbs. Only these two — the
    /// inflected forms (`does`, `did`, `has`, `had`) cannot open an imperative.
    private static let imperativeHeads: Set<String> = ["do", "have"]

    /// Objects that make one of the above an instruction rather than a question:
    /// "do it", "have them look at it". A pronoun subject like "you" or "we" is
    /// deliberately absent, so "do you have a minute?" still gets its mark.
    private static let imperativeObjects: Set<String> = [
        "it", "this", "that", "these", "those", "them"
    ]

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

    /// Interjections and discourse openers that sit in front of a question
    /// without changing it: "hey can you cover for me" is still a question.
    /// Measured: without this, the model's own "?" was the only thing catching
    /// these, and it dropped them 3/3 in casual chat.
    private static let leadingInterjections: Set<String> = [
        "hey", "yo", "hi", "hello", "okay", "ok", "so", "well", "oh", "ah",
        "um", "uh", "hmm", "alright", "aight", "man", "bro", "dude", "bruh",
        "and", "but", "also", "actually", "honestly", "wait", "yeah", "yo",
        "please", "quick", "real"
    ]

    static func looksLikeQuestion(_ sentence: String) -> Bool {
        let stripped = sentence.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'“”‘’([{ \t")
        )
        var words = stripped.split { $0 == " " || $0.isNewline }.map(String.init)
        // Drop at most two leading interjections, never the whole sentence, so
        // "okay so can you send it" is tested as "can you send it".
        var dropped = 0
        while dropped < 2, words.count > 1 {
            let head = words[0].lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:'"))
            guard leadingInterjections.contains(head) else { break }
            words.removeFirst()
            dropped += 1
        }
        guard let rawFirst = words.first else { return false }
        let w0 = rawFirst.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:'"))
        let w1 = words.count > 1
            ? words[1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:'"))
            : ""

        // An imperative, not an inversion. "do it", "do that", "have it write
        // the test first" are instructions, and they were getting a question
        // mark — in `codeOrTerminal`, where this profile is on by default and
        // "do it" is one of the most common things Bryce says to Claude Code.
        // A stray "?" cannot corrupt a shell command, which is what the comment
        // at the call site relies on, but a Claude Code prompt is not a shell
        // command and "do it?" reads as hesitation.
        //
        // Bare forms only. `does`, `did`, `has` and `had` are never imperative,
        // so "did it work?" and "does that make sense?" are untouched.
        if imperativeHeads.contains(w0), imperativeObjects.contains(w1) { return false }
        // wh-question, but not an instructional infinitive ("how to reset …")
        // and not an exclamative ("What a mess", "How a build works").
        if whWords.contains(w0) {
            // "when" is the one wh-word that opens a subordinate clause on a
            // statement more often than it opens a question: "when I get back
            // I'll look at it".
            //
            // Measured 2026-08-08 against 782 wh-initial sentences taken from
            // Bryce's own accepted output, scored on whether HE kept a "?":
            //
            //     head    total   false+ before   after
            //     when       75       47           1
            //
            // 46 fixed against 3 questions lost. The other heads are left
            // alone, and that is measured too, not an omission: extending this
            // same gate to every wh-word takes the whole set from 31 false
            // positives to 20 — while taking false NEGATIVES from 10 to 122.
            // "what I need is X" is a free relative and "which doesn't work" is
            // a fragment, but both are rare next to the real questions the gate
            // would silently stop punctuating. Do not widen this without
            // re-running that measurement.
            //
            // Subject-auxiliary inversion is what separates the two. A question
            // inverts — "when do I", "when is it", "when can we" — and the aux
            // can sit a word or two back ("when exactly do you need it", "when
            // the hell did that happen"). A subordinate clause keeps subject
            // order and never inverts: "when I get back", "when the build
            // finishes". So require an inversion somewhere, not just at w1.
            if w0 == "when", !w1.isEmpty, !auxiliaries.contains(w1),
               !hasInversion(in: words, after: 1) {
                return false
            }
            return w1 != "to" && !((w0 == "what" || w0 == "how") && (w1 == "a" || w1 == "an"))
        }
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

    /// Subject-auxiliary inversion anywhere after `index` — "…can you send it",
    /// "…did that happen", "…do you need it".
    ///
    /// Only the "when" rule needs this. Testing w1 alone would have thrown away
    /// three shapes the shipped rule already got right: an adverb between the
    /// wh-word and the aux ("when exactly do you need it"), an expletive ("when
    /// the hell did that happen"), and a subordinate clause parked in front of a
    /// real question ("when you get a chance can you send that over").
    private static func hasInversion(in words: [String], after index: Int) -> Bool {
        guard words.count > index + 2 else { return false }
        let edges = CharacterSet(charactersIn: ".,!?;:'")
        for i in (index + 1)..<(words.count - 1) {
            let aux = words[i].lowercased().trimmingCharacters(in: edges)
            let subject = words[i + 1].lowercased().trimmingCharacters(in: edges)
            guard auxiliaries.contains(aux), subjects.contains(subject) else { continue }
            // "…I'll do it", "…I'll have it done" — the same imperative pair the
            // head-word check rejects at position 0, riding inside a main clause.
            if imperativeHeads.contains(aux), imperativeObjects.contains(subject) { continue }
            return true
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
