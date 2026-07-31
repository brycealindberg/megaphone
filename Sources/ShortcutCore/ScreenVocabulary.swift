import Foundation
import NaturalLanguage

/// Turns the text visible in the frontmost window into a short list of proper
/// nouns worth biasing the recogniser toward.
///
/// The case this exists for is the name you are looking at while you dictate —
/// a colleague in a Slack thread, a client on an invoice, a library in a code
/// review. Those are exactly the words a general speech model gets wrong, and
/// exactly the words the screen in front of you already spells correctly.
///
/// Extraction is deliberately conservative. Everything here competes with the
/// user's own dictionary for the recogniser's attention, so a wall of window
/// chrome ("Inbox", "Send", "Search") must never crowd out a real term.
enum ScreenVocabulary {
    /// Contextual-string slots spent on screen text. `contextualStrings` itself
    /// is uncapped, so this limit is not an API constraint — it keeps a busy
    /// window from diluting the bias the dictionary is supposed to provide.
    static let limit = 48

    /// Longest phrase kept whole. Beyond four words a match is prose, not a name.
    private static let maxWords = 4
    private static let minLength = 3
    private static let maxLength = 64

    /// - Parameters:
    ///   - screenText: whatever `ScreenTextService` could read, already truncated.
    ///   - existing: terms the recogniser is biased toward anyway. Excluded so
    ///     the dictionary never spends a screen slot on itself.
    static func terms(
        from screenText: String,
        excluding existing: [String] = [],
        limit: Int = limit
    ) -> [String] {
        let text = screenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, limit > 0 else { return [] }

        var taken = Set(existing.map { $0.lowercased() })
        var ordered: [String] = []

        func offer(_ candidate: String, requireCapital: Bool = true) {
            guard ordered.count < limit else { return }
            let term = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: Self.edgePunctuation)
            guard isUsable(term, requireCapital: requireCapital) else { return }
            guard taken.insert(term.lowercased()).inserted else { return }
            ordered.append(term)
        }

        // Whole names first: "Rosen Uzunov" is a better bias than either half.
        let names = taggedNames(in: text)
        for name in names { offer(name) }
        // Then the parts, because you rarely say someone's surname out loud.
        for name in names where name.contains(" ") {
            for part in name.split(separator: " ") { offer(String(part)) }
        }
        // Then the words no name tagger will ever catch: product and tool
        // spellings the recogniser has no lexicon entry for.
        for token in unusualSpellings(in: text) { offer(token, requireCapital: false) }
        // Last, and lowest priority, the ordinary-looking capitals: a company
        // or tool that only a mid-sentence capital gives away.
        for token in midSentenceCapitals(in: text) { offer(token) }

        return ordered
    }

    // MARK: Sources

    private static func taggedNames(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        // Screen text is chrome and fragments, not prose, and NLTagger's own
        // language guess fails on it *silently* — it returns no names at all
        // rather than erroring. NLLanguageRecognizer still gets it right on the
        // same input, so pin the language before tagging.
        tagger.setLanguage(dominantLanguage(of: text), range: text.startIndex..<text.endIndex)
        var found: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            guard let tag,
                  tag == .personalName || tag == .placeName || tag == .organizationName else {
                return true
            }
            found.append(String(text[range]))
            return true
        }
        return found
    }

    private static func dominantLanguage(of text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .english
    }

    /// Tokens whose *shape* says the recogniser will not have them: an
    /// internal capital ("DisclosureIQ", "GitHub") or letters mixed with digits
    /// ("n8n", "m4a"). A structural test rather than a spell check, so it costs
    /// nothing and never asks a dictionary what a word is.
    private static func unusualSpellings(in text: String) -> [String] {
        var found: [String] = []
        let tokens = text.split { character in
            !(character.isLetter || character.isNumber || character == "-" || character == "_")
        }
        for token in tokens {
            let word = String(token)
            guard hasInternalCapital(word) || mixesLettersAndDigits(word) else { continue }
            found.append(word)
        }
        return found
    }

    /// Capitalised words that are *not* starting a sentence — "the Deepgram
    /// swap", "the Upwork escrow". A capital in that position is a proper noun
    /// far more often than not, whereas a line-initial capital says nothing,
    /// which is precisely where window chrome lives ("Inbox", "Compose").
    private static func midSentenceCapitals(in text: String) -> [String] {
        var found: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            var startsSentence = true
            for rawToken in line.split(separator: " ") {
                let token = String(rawToken).trimmingCharacters(in: edgePunctuation)
                // A sentence ends where the *untrimmed* token does, so decide
                // the next token's status before moving on.
                let endsSentence = rawToken.hasSuffix(".") || rawToken.hasSuffix("!")
                    || rawToken.hasSuffix("?") || rawToken.hasSuffix(":")
                defer { startsSentence = endsSentence }
                guard !startsSentence, !token.isEmpty else { continue }
                guard token.first?.isUppercase == true else { continue }
                // All-caps is emphasis or an acronym already covered elsewhere.
                guard token.contains(where: \.isLowercase) else { continue }
                found.append(token)
            }
        }
        return found
    }

    private static func hasInternalCapital(_ word: String) -> Bool {
        guard word.count > 1 else { return false }
        let letters = Array(word)
        // Skip SHOUTING and Ordinary Capitalisation; only a capital that
        // follows a lowercase letter marks a deliberate spelling.
        for index in 1..<letters.count where letters[index].isUppercase && letters[index - 1].isLowercase {
            return true
        }
        return false
    }

    /// A tool name carries more letters than digits ("n8n", "m4a"). A terminal
    /// is full of the opposite — "430k", "36h", "ttys023" — and none of those
    /// is ever a word anyone says.
    private static func mixesLettersAndDigits(_ word: String) -> Bool {
        let letters = word.count(where: \.isLetter)
        let digits = word.count(where: \.isNumber)
        return letters >= 2 && digits >= 1 && letters >= digits
    }

    // MARK: Filtering

    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'’“”()[]{}<>-–—•*_/\\|")

    private static func isUsable(_ term: String, requireCapital: Bool) -> Bool {
        guard term.count >= minLength, term.count <= maxLength else { return false }
        guard term.contains(where: \.isLetter) else { return false }
        // An address or path is on screen constantly and is never what you said.
        guard !term.contains("@"), !term.contains("/"), !term.contains("\\"),
              !term.lowercased().contains(".com"), !term.lowercased().contains("www.") else {
            return false
        }

        let words = term.split(separator: " ")
        guard !words.isEmpty, words.count <= maxWords else { return false }
        if requireCapital, term.first?.isUppercase != true { return false }
        // "The Interior's House" survives its leading article; a bare "The"
        // does not. Reject only when every word is chrome.
        guard words.contains(where: { !isStopWord($0) }) else { return false }
        return true
    }

    /// A contraction is chrome if its stem is: "I'll" is not a name, and the
    /// apostrophe is what hides it from a plain stop-word lookup.
    private static func isStopWord(_ word: some StringProtocol) -> Bool {
        let lowered = word.lowercased()
        if stopWords.contains(lowered) { return true }
        guard let apostrophe = lowered.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) else {
            return false
        }
        return stopWords.contains(String(lowered[lowered.startIndex..<apostrophe]))
    }

    /// Capitalised words that appear in almost every window and name nobody.
    /// Interface chrome first, then the sentence-initial words a name tagger
    /// mistakes for organisations.
    private static let stopWords: Set<String> = [
        // Window and menu chrome
        "inbox", "sent", "drafts", "archive", "trash", "spam", "starred", "search",
        "settings", "preferences", "general", "help", "file", "edit", "view", "window",
        "new", "open", "close", "save", "cancel", "done", "ok", "okay", "yes", "no",
        "send", "reply", "forward", "delete", "share", "copy", "paste", "cut", "undo",
        "back", "next", "previous", "home", "menu", "more", "less", "all", "none",
        "add", "remove", "create", "update", "upload", "download", "import", "export",
        "sign", "log", "login", "logout", "account", "profile", "notifications",
        "today", "yesterday", "tomorrow", "now", "online", "offline", "away", "active",
        "untitled", "loading", "error", "warning", "success", "failed", "pending",
        "succeeded", "completed", "finished", "started", "stopped", "saved", "copied",
        "connected", "disconnected", "read", "unread", "enabled", "disabled",
        "name", "email", "phone", "address", "title", "subject", "message", "notes",
        "to", "from", "cc", "bcc", "re", "fwd",
        // Ordinary English that starts sentences
        "the", "a", "an", "and", "or", "but", "if", "then", "so", "for", "of", "in",
        "on", "at", "by", "with", "this", "that", "these", "those", "it", "its",
        "i", "you", "we", "they", "he", "she", "him", "her", "his", "them", "us",
        "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does",
        "did", "will", "would", "can", "could", "should", "may", "might", "must",
        "what", "when", "where", "who", "why", "how", "which", "there", "here",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
    ]
}
