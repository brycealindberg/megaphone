import Foundation

/// Lowercases the first letter of a dictation that continues a sentence already
/// underway in the field — typing "I was thinking we could" and then dictating
/// "meet at the office" should insert "meet…", not "Meet…".
///
/// The caret context needed for this is already captured
/// (`AppContext.textBeforeCaret`) and already handed to the cleanup model, whose
/// instructions ask it to continue existing text with matching capitalization.
/// It does that inconsistently, and the fix belongs in the same place every
/// other precise casing/punctuation rule in this app ended up: deterministic
/// code that can only do the one thing.
///
/// The whole design is biased in one direction: **when unsure, leave the capital
/// alone.** A missed lowercase looks like today's behaviour; wrongly writing
/// "i talked to devon" mangles a name and is far more annoying to fix. So a word
/// is lowercased only when nothing suggests it is a proper noun.
enum SentenceContinuation {

    // MARK: - entry point

    /// - Parameters:
    ///   - text: the finished dictation, about to be inserted at the caret.
    ///   - textBeforeCaret: the field's existing text immediately before the
    ///     caret, or nil when the app exposes none (web views, most terminals),
    ///     in which case nothing happens.
    ///   - protectedTerms: the user's dictation vocabulary. Capitalized entries
    ///     are treated as proper nouns and keep their capital.
    static func adjust(
        _ text: String,
        textBeforeCaret: String?,
        protectedTerms: [String] = []
    ) -> String {
        guard continuesSentence(textBeforeCaret) else { return text }
        // The first run of letters, skipping any opening quote or bracket the
        // cleanup may have added.
        guard let letterIndex = text.firstIndex(where: { $0.isLetter }) else { return text }
        let wordEnd = text[letterIndex...].firstIndex(where: { !$0.isLetter && $0 != "'" && $0 != "’" })
            ?? text.endIndex
        let word = String(text[letterIndex..<wordEnd])
        guard shouldLowercase(word, protectedTerms: protectedTerms) else { return text }

        var result = text
        let lowered = String(result[letterIndex]).lowercased()
        result.replaceSubrange(letterIndex...letterIndex, with: lowered)
        return result
    }

    // MARK: - is a sentence already underway?

    /// True when the text before the caret ends mid-sentence.
    ///
    /// Deliberately a whitelist of "this sentence is still open" endings rather
    /// than a blacklist of terminators: an unrecognised trailing character means
    /// no change, which is the safe direction. Only spaces and tabs are trimmed
    /// — a trailing newline is a fresh line and must stay a fresh start.
    static func continuesSentence(_ textBeforeCaret: String?) -> Bool {
        guard let raw = textBeforeCaret else { return false }
        var trimmed = raw
        while let last = trimmed.last, last == " " || last == "\t" {
            trimmed.removeLast()
        }
        guard let last = trimmed.last else { return false }
        // A letter or digit: plainly mid-sentence ("I was thinking we could").
        if last.isLetter || last.isNumber { return true }
        // Punctuation that opens rather than closes a clause. A comma, colon or
        // semicolon is always followed by lowercase; "&" and "/" sit mid-phrase.
        //
        // Everything else falls through to false on purpose, including:
        //   . ! ? …   a finished sentence
        //   \n        a new line
        //   - * •     a list bullet
        //   " “ ' ( [ an opening quote or bracket — "he said, "We should go""
        //   $ % # >   a shell prompt, so a terminal's first word keeps its capital
        return ",;:&/".contains(last)
    }

    // MARK: - is this word safe to lowercase?

    static func shouldLowercase(_ word: String, protectedTerms: [String] = []) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        let lower = word.lowercased()

        // "I", "I'm", "I'll" are always capitalized.
        if lower == "i" || lower.hasPrefix("i'") || lower.hasPrefix("i’") { return false }

        // A function word is lowercased even when it collides with a vocabulary
        // entry. This matters concretely: "Will" is in the dictionary as a name,
        // and without this "I think we will" would become "I think we Will".
        if functionWords.contains(lower) { return true }

        // An internal capital means an acronym or a brand: API, SOW, GitHub,
        // McDonald. Never touched.
        if word.dropFirst().contains(where: { $0.isUppercase }) { return false }

        if daysAndMonths.contains(lower) { return false }
        if protectedFirstWords(protectedTerms).contains(lower) { return false }
        return true
    }

    /// Vocabulary entries that look like proper nouns, reduced to their first
    /// word — "Wispr Flow" protects "wispr", "Claude Code" protects "claude" —
    /// with trailing punctuation dropped so the entry "Devon." still protects
    /// "devon".
    static func protectedFirstWords(_ terms: [String]) -> Set<String> {
        var result: Set<String> = []
        for term in terms {
            guard let head = term.split(separator: " ").first else { continue }
            let cleaned = head.trimmingCharacters(in: CharacterSet.letters.inverted.subtracting(
                CharacterSet(charactersIn: "'’")
            ))
            guard let first = cleaned.first, first.isUppercase else { continue }
            result.insert(cleaned.lowercased())
        }
        return result
    }

    /// Words that are never proper nouns at the start of a continuation.
    /// Overrides the vocabulary, so common words that happen to be in the
    /// dictionary ("Will", "Code", "Walk", "Berry") still lowercase correctly.
    static let functionWords: Set<String> = [
        // articles, conjunctions, prepositions
        "a", "an", "the", "and", "or", "nor", "but", "so", "yet", "if", "then",
        "than", "that", "this", "these", "those", "because", "since", "while",
        "unless", "until", "though", "although", "whether", "as",
        "for", "to", "of", "in", "on", "at", "by", "with", "from", "into",
        "onto", "about", "after", "before", "during", "over", "under", "up",
        "out", "off", "down", "between", "through", "across", "around", "via",
        // pronouns and determiners
        "it", "its", "we", "our", "ours", "you", "your", "yours", "they",
        "them", "their", "theirs", "he", "him", "his", "she", "her", "hers",
        "my", "mine", "me", "us", "there", "here", "who", "whom", "whose",
        "what", "which", "when", "where", "why", "how",
        "all", "any", "both", "each", "every", "some", "no", "none", "one",
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "more", "most", "less", "least", "much", "many", "few", "several",
        "other", "another", "same", "such", "own",
        // auxiliaries and modals
        "is", "am", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "doing", "done",
        "have", "has", "had", "having",
        // "may" is deliberately absent: it collides with the month, and the
        // function-word list wins over `daysAndMonths`. Leaving it out keeps
        // "see you in May" safe at the cost of "May" the modal keeping a capital.
        "can", "could", "will", "would", "shall", "should", "might",
        "must", "ought",
        // very common verbs, in the forms a continuation actually starts with
        "go", "going", "goes", "went", "get", "getting", "gets", "got",
        "make", "making", "makes", "made", "take", "taking", "takes", "took",
        "give", "giving", "gives", "gave", "come", "coming", "comes", "came",
        "see", "seeing", "sees", "saw", "know", "knowing", "knows", "knew",
        "think", "thinking", "thinks", "thought", "want", "wants", "wanted",
        "need", "needs", "needed", "try", "trying", "tries", "tried",
        "say", "saying", "says", "said", "tell", "telling", "tells", "told",
        "ask", "asking", "asks", "asked", "put", "putting", "puts",
        "send", "sending", "sends", "sent", "meet", "meeting", "meets", "met",
        "grab", "grabbing", "grabs", "grabbed", "run", "running", "runs", "ran",
        "check", "checking", "checks", "checked", "add", "adding", "adds",
        "added", "use", "using", "uses", "used", "work", "working", "works",
        "worked", "call", "calling", "calls", "called", "start", "starting",
        "starts", "started", "finish", "finishing", "finished", "keep",
        "keeping", "keeps", "kept", "look", "looking", "looks", "looked",
        "feel", "feeling", "feels", "felt", "sound", "sounds", "sounded",
        "let", "lets", "let's", "let’s", "leave", "leaving", "left",
        "move", "moving", "moved", "set", "setting", "sets",
        "find", "finding", "finds", "found", "show", "showing", "shows",
        "showed", "help", "helping", "helps", "helped", "build", "building",
        "builds", "built", "write", "writing", "writes", "wrote",
        "read", "reading", "reads", "fix", "fixing", "fixes", "fixed",
        "ship", "shipping", "ships", "shipped", "walk", "walking", "walks",
        "code", "coding", "talk", "talking", "talks", "talked",
        // adverbs and hedges
        "just", "also", "too", "very", "really", "actually", "basically",
        "honestly", "maybe", "probably", "definitely", "pretty", "kind",
        "kinda", "sorta", "still", "already", "always", "never", "sometimes",
        "again", "even", "only", "almost", "instead", "anyway", "anyways",
        "not", "now", "soon", "later", "today", "tomorrow", "yesterday",
        "well", "okay", "yeah", "yep", "nope", "nah", "please", "thanks"
    ]

    /// Capitalized in every position, so they are never lowercased even though
    /// they are ordinary words.
    static let daysAndMonths: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        "sunday", "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri",
        "sat", "sun",
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept",
        "oct", "nov", "dec"
    ]
}
