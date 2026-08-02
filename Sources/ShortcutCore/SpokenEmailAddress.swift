import Foundation

/// Joins a spoken email address: "my email is marek at kestrel.dev" becomes
/// "my email is marek@kestrel.dev".
///
/// The cleanup model already does this — but only sometimes, which is worse than
/// never, because the case you try first is the one it gets right. Measured on
/// the shipped pipeline:
///
/// ```
/// send it to hello at doubleclick dot ai      -> hello@doubleclick.ai   assembled
/// email me at support at example.com please   -> support@example.com    assembled
/// My email is <name> at gmail.com             -> unchanged
/// let's meet at gmail.com headquarters        -> unchanged, correctly
/// ```
///
/// So a deterministic pass has to subsume what the model already gets right,
/// **including its refusals** — that last line is ordinary prose and must stay
/// ordinary prose.
///
/// The guard is an anchor word appearing *before* the match, the same shape that
/// keeps `SpokenEmoji` safe. "let's meet at gmail.com headquarters" has none, so
/// nothing fires. A domain check alone cannot save it, because "meet at
/// gmail.com" is exactly the shape being matched.
///
/// Known limit: only a single-token local part. When the recogniser mishears a
/// name into several words, "<first> <middle> <last> at kestrel.dev" joins just
/// the last one. Guessing which words belong to the address would invent one, so
/// the repair for a specific person is a `word_corrections` entry instead — and
/// this pass runs *after* those, so it cannot get in their way.
enum SpokenEmailAddress {
    /// One of these must appear before the match. Without it the phrase is just
    /// a preposition and a domain-shaped noun.
    private static let anchors: Set<String> = [
        "email", "emails", "e-mail", "mail", "mailed", "address", "addresses",
        "contact", "reach", "send", "sent", "cc", "bcc", "forward", "invite",
    ]

    /// Never the local part: these are the object of "at", not an address.
    private static let notLocalParts: Set<String> = [
        "me", "us", "him", "her", "them", "you", "it", "everyone", "someone",
        "anyone", "myself", "yourself", "himself", "herself", "themselves",
    ]

    private static let topLevelDomains: Set<String> = [
        "com", "net", "org", "io", "ai", "co", "dev", "app", "me", "uk", "us",
        "ca", "de", "fr", "nl", "edu", "gov", "info", "biz", "xyz", "cloud",
    ]

    static func assemble(_ text: String) -> String {
        // Cheap exit: no " at " means nothing to join.
        guard text.range(of: #"(?<![\p{L}\p{N}])at(?![\p{L}\p{N}])"#,
                         options: [.regularExpression, .caseInsensitive]) != nil else { return text }

        var tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var sawAnchor = false
        var index = 0

        while index < tokens.count {
            let bare = strip(tokens[index]).lowercased()
            if anchors.contains(bare) { sawAnchor = true }

            guard sawAnchor, bare == "at", index > 0, index + 1 < tokens.count else {
                index += 1
                continue
            }
            let local = strip(tokens[index - 1])
            guard isLocalPart(local) else { index += 1; continue }
            guard let domain = domain(from: tokens, startingAt: index + 1) else { index += 1; continue }

            // Whatever punctuation trailed the last domain token stays outside
            // the address: "gmail.com." keeps its full stop.
            let tail = trailing(tokens[domain.lastIndex])
            tokens.replaceSubrange((index - 1)...domain.lastIndex, with: [local + "@" + domain.text + tail])
            // The address now sits at index - 1 and the array is strictly
            // shorter, so leaving `index` alone both makes progress and points
            // at the next unexamined token.
        }
        return tokens.joined(separator: " ")
    }

    /// A single token that could be the left of an "@": letters, digits, and the
    /// punctuation addresses actually use.
    private static func isLocalPart(_ token: String) -> Bool {
        guard token.count >= 2, !token.contains("@"),
              !notLocalParts.contains(token.lowercased()),
              token.first?.isLetter == true || token.first?.isNumber == true
        else { return false }
        return token.allSatisfy { $0.isLetter || $0.isNumber || "._-+".contains($0) }
    }

    /// A domain starting at `start`, either "example.com" or the spoken
    /// "example dot com". Returns the joined text and the last token consumed.
    private static func domain(from tokens: [String], startingAt start: Int) -> (text: String, lastIndex: Int)? {
        let first = strip(tokens[start]).lowercased()

        if let dot = first.lastIndex(of: "."), dot != first.startIndex {
            let tld = String(first[first.index(after: dot)...])
            let host = String(first[first.startIndex..<dot])
            if topLevelDomains.contains(tld), isHost(host) { return (first, start) }
            return nil
        }
        // "doubleclick dot ai"
        guard isHost(first), start + 2 < tokens.count,
              strip(tokens[start + 1]).lowercased() == "dot" else { return nil }
        let tld = strip(tokens[start + 2]).lowercased()
        guard topLevelDomains.contains(tld) else { return nil }
        return (first + "." + tld, start + 2)
    }

    private static func isHost(_ host: String) -> Bool {
        !host.isEmpty && host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
    }

    private static let edgePunctuation = CharacterSet(charactersIn: ",;:!?\"'“”‘’()[]{}")

    /// The token with sentence punctuation removed, keeping a domain's internal
    /// dots: "gmail.com." becomes "gmail.com", "please." becomes "please".
    private static func strip(_ token: String) -> String {
        var value = token.trimmingCharacters(in: edgePunctuation)
        if value.hasSuffix(".") { value.removeLast() }
        return value
    }

    /// Punctuation that trailed a token and must survive outside the address.
    private static func trailing(_ token: String) -> String {
        let core = strip(token)
        guard let range = token.range(of: core) else { return "" }
        return String(token[range.upperBound...])
    }
}
