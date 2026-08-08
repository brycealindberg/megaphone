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

    /// Terms used to address a person directly. A comma right after one of these
    /// is a vocative and Bryce keeps it — "no worries man, all good".
    static let addressTerms: Set<String> = [
        "man", "bro", "dude", "bruh", "brother", "sir", "maam", "guys",
        "everyone", "team", "buddy", "boss", "fam", "bud"
    ]

    /// Greetings that can be followed by the name of the person being addressed.
    /// Deliberately smaller than `leadingOpeners`: this list only decides whether
    /// a capitalised word after it is a name.
    static let addressGreetings: Set<String> = [
        "hey", "hi", "hello", "yo", "hiya", "heya", "sup", "morning", "evening"
    ]

    static func lighten(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        // Decided on the ORIGINAL text, before any rule has deleted anything.
        // The opener rule runs first and removes one comma, which could drop a
        // real list from two commas (protected) to one (unprotected) — and the
        // short-message rule then ate the survivor:
        //     "Okay, I grabbed eggs, milk and bread" -> "…eggs milk and bread"
        //     "Word, Excel, and PowerPoint"          -> "Word Excel and PowerPoint"
        // The existing guard test could never catch this: its fixture opens with
        // "Sorry," which is not in `leadingOpeners`, so the first rule never
        // fired and the shadowing path was never executed.
        let listProtected = looksLikeList(text)
        var result = stripLeadingOpenerComma(text, listProtected: listProtected)
        result = stripShortMessageCommas(result, listProtected: listProtected)
        result = stripPolitenessCommas(result)
        return result
    }

    /// Whether the text reads as a genuine enumeration whose commas carry
    /// meaning, rather than stacked discourse commas.
    ///
    /// Two signals, both requiring two or more commas: a coordinating
    /// "and"/"or"/"nor", or a colon introducing the list before the first comma.
    static func looksLikeList(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![0-9]),(?![0-9])"#) else { return false }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return false }
        if text.range(of: #"\b(and|or|nor)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let colon = ns.range(of: ":")
        return colon.location != NSNotFound && colon.location < matches[0].range.location
    }

    /// Whether the WHOLE text is nothing but a comma-separated enumeration of
    /// short items — "Word, Excel, and PowerPoint" — as opposed to a sentence
    /// that merely contains a list ("Okay, I grabbed eggs, milk and bread").
    ///
    /// This is the strictly narrower half of `looksLikeList`, and it exists for
    /// exactly one caller: the opener rule, which needs to know whether the
    /// first comma is an ITEM SEPARATOR rather than a discourse comma. Four
    /// signals, all required, each one keeping out a shape that a probe showed
    /// the looser version swallowing:
    ///
    ///   - three or more chunks, i.e. the two commas `looksLikeList` wants;
    ///   - every chunk is at most two words and carries no sentence punctuation
    ///     (`. ! ? : ;` or a line break), so prose cannot pass as an item.
    ///     Two words, not three: raising it to three admits "I grabbed eggs" and
    ///     keeps the comma in "Okay, I grabbed eggs, milk, and bread", which the
    ///     corpus-tuned behaviour drops;
    ///   - the last chunk holds the coordinating and/or/nor that closes an
    ///     enumeration, either alone ("and PowerPoint") or joining the final
    ///     pair when there is no Oxford comma ("PowerPoint and Outlook"). This
    ///     is what keeps "Yeah, for sure, I'll send it tonight" out: short
    ///     chunks, no coordinator, stacked discourse;
    ///   - no item AFTER the first begins with a lowercase letter. A dictation
    ///     capitalises its first word whatever that word is, so the first item's
    ///     capital carries no information; the ones behind it do. "Excel" and
    ///     "PowerPoint" capitalised mid-line are proper nouns being enumerated,
    ///     while "Okay, eggs, milk, and bread" and "Anyway, gym, and groceries"
    ///     are a genuine opener in front of a list — measured only in the sense
    ///     that the probe run showed those two changing, and they must not.
    ///
    /// Two residuals this deliberately leaves open, because closing either is a
    /// guess without corpus evidence:
    ///   - an all-lowercase list whose first item is an opener word ("well,
    ///     pump, or pipe") still loses its first comma. Protecting it would
    ///     require giving up the capitalisation signal, which costs the two
    ///     genuine openers above;
    ///   - a particle after the list ("Word, Excel, and PowerPoint, please")
    ///     puts the coordinator in the second-to-last chunk, so the shape is not
    ///     recognised.
    static func readsAsEnumeratedItems(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![0-9]),(?![0-9])"#) else { return false }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return false }

        // Split on the same non-numeric commas, so "1,000" stays inside one item.
        var chunks: [String] = []
        var cursor = 0
        for match in matches {
            let length = match.range.location - cursor
            guard length >= 0 else { return false }
            chunks.append(ns.substring(with: NSRange(location: cursor, length: length)))
            cursor = match.range.location + match.range.length
        }
        chunks.append(ns.substring(from: cursor))

        func isShortItem(_ chunk: String) -> Bool {
            let item = chunk.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { return false }
            guard item.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?:;\n\r\t")) == nil else {
                return false
            }
            return item.split(whereSeparator: { $0.isWhitespace }).count <= 2
        }
        /// A digit or symbol start is neutral — "Word, 365 Suite, and Teams" is
        /// still an enumeration. Only an actual lowercase letter disqualifies.
        /// ("Word, 365, and Teams" never gets this far: a comma sitting directly
        /// after a digit is a number comma to every rule in this file.)
        func startsLowercase(_ chunk: String) -> Bool {
            chunk.trimmingCharacters(in: .whitespaces).first?.isLowercase == true
        }

        for chunk in chunks.dropLast() where !isShortItem(chunk) { return false }
        for chunk in chunks.dropFirst().dropLast() where startsLowercase(chunk) { return false }

        let last = chunks[chunks.count - 1]
        guard let coordinator = last.range(
            of: #"\b(?:and|or|nor)\b"#, options: [.regularExpression, .caseInsensitive]
        ) else { return false }
        let before = String(last[last.startIndex..<coordinator.lowerBound])
        let after = String(last[coordinator.upperBound...])
        let beforeIsEmpty = before.trimmingCharacters(in: .whitespaces).isEmpty
        guard beforeIsEmpty || (isShortItem(before) && !startsLowercase(before)) else { return false }
        return isShortItem(after) && !startsLowercase(after)
    }

    // MARK: - leading opener

    /// "Okay, bet I will" -> "Okay bet I will". Removes exactly the comma that
    /// sits right after a leading interjection, preserving its original case.
    ///
    /// `listProtected` is the caller's `looksLikeList` verdict on the ORIGINAL
    /// text. Until 2026-08-07 only `stripShortMessageCommas` was given it, so
    /// this rule ran blind and ate the FIRST comma of any list whose first item
    /// happens to also be an opener word — "word", "man", "no", "so", "well" and
    /// "nice" are all ordinary nouns and adverbs:
    ///     "Word, Excel, and PowerPoint"      -> "Word Excel, and PowerPoint"
    ///     "Word, Excel, PowerPoint and Outlook" -> "Word Excel, PowerPoint …"
    ///     "Man, Kestrel, and Whitfield"      -> "Man Kestrel, and Whitfield"
    /// The identical lists starting on a non-opener ("Excel, Word, and
    /// PowerPoint") came through untouched, which is what makes it a defect in
    /// this rule and not a judgement call about lists. `readsAsEnumeratedItems`
    /// documents exactly how much of that class is now covered — the lowercase
    /// half of it deliberately is not.
    static func stripLeadingOpenerComma(_ text: String, listProtected: Bool = false) -> String {
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

        // The list guard. Both halves are required: `listProtected` alone is far
        // too broad — it is true of "Okay, I grabbed eggs, milk and bread",
        // where the opener is a genuine opener and its comma must still go
        // (measured fixture, see testOpenerCannotUnprotectAList).
        //
        // A greeting is carved back out. "Hi, Dana, and Marek" has the shape of
        // an enumeration and is really a greeting in front of two names — and
        // this file already measured that exact comma over 9,804 dictations: a
        // bare greeting comma is one Bryce CUTS, 54 to 15. So a greeting keeps
        // losing it, and only the non-greeting openers get the protection.
        //
        // The accepted cost: a NON-greeting opener in front of two capitalised
        // names ("No worries, Kestrel, and Whitfield") now keeps its comma.
        // Nothing here can tell a name from a product noun — "Excel" and
        // "Kestrel" look identical — and `addressGreetings` is deliberately the
        // only place in this file that guess is made.
        let opener = ns.substring(with: match.range)
            .lowercased()
            .filter { $0.isLetter || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
        if listProtected, !addressGreetings.contains(opener), readsAsEnumeratedItems(text) {
            return text
        }

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
    static func stripShortMessageCommas(_ text: String, listProtected: Bool = false) -> String {
        // Splits on ALL whitespace: counting only spaces and newlines let a
        // tab- or NBSP-separated line read as one word and bypass the gate.
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount <= maxShortMessageWords else { return text }

        // Commas that are not between two digits — i.e. not "1,000".
        guard let regex = try? NSRegularExpression(pattern: #"(?<![0-9]),(?![0-9])"#) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        // A genuine list keeps its commas. Judged on the caller's view of the
        // ORIGINAL text as well as this one, so an opener comma already removed
        // upstream cannot disguise a list as stacked discourse.
        if listProtected || looksLikeList(text) { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() where !closesDirectAddress(ns, commaAt: match.range.location) {
            mutable.deleteCharacters(in: match.range)
        }
        return collapseSpaces(mutable as String)
    }

    /// Whether the comma at `commaAt` closes a direct address, which is the one
    /// short-message comma Bryce reliably keeps.
    ///
    /// Measured over 9,804 real dictations, counting only the commas this rule
    /// already removes and comparing against the text he actually kept:
    ///
    ///     "Hey <Name>, how's it going?" greeting + name   18 kept,  0 cut  100%
    ///     "Hey man, how are you?"       greeting + term    4 kept,  0 cut  100%
    ///     "no worries man, all good"    address term      38 kept,  6 cut   86%
    ///
    /// Two neighbouring shapes are deliberately NOT protected, because the same
    /// measurement says he cuts them:
    ///
    ///     "Hey, how are you doing?"     bare greeting     15 kept, 54 cut   22%
    ///     "Thanks for reaching out, <Name>."  trailing name 11 kept, 20 cut  35%
    ///
    /// Net over the corpus: 62 wrong removals fixed against 7 right ones lost,
    /// 8.9:1, taking this pass from 85.0% to 87.2% precision. The earlier 90%
    /// figure came from the 120-clip corpus, which is terminal-framed and holds
    /// almost no greetings — it could not see this class at all.
    static func closesDirectAddress(_ ns: NSString, commaAt: Int) -> Bool {
        func bare(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        func isWordCharacter(_ index: Int) -> Bool {
            guard let scalar = UnicodeScalar(ns.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "\u{2019}"
        }

        // The word immediately in front of the comma.
        var end = commaAt
        while end > 0, !isWordCharacter(end - 1) { end -= 1 }
        var start = end
        while start > 0, isWordCharacter(start - 1) { start -= 1 }
        guard start < end else { return false }
        let previous = ns.substring(with: NSRange(location: start, length: end - start))
        if addressTerms.contains(bare(previous)) { return true }

        // Or a capitalised name directly after an opening greeting. Bounded to
        // the first few words so a capitalised word deep in the sentence — a
        // product, a day of the week — cannot pass as someone being addressed.
        guard previous.first?.isUppercase == true else { return false }
        let head = ns.substring(to: start)
        let leading = head.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init)
        guard let opener = leading.first, addressGreetings.contains(bare(opener)) else { return false }
        return leading.count <= 2
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
        // Sentence-FINAL only. As a bare lookahead this also fired on the
        // particle opening a following clause, where the comma is required:
        //   "The deck is ready, though the pricing page still needs work"
        //   "If you could review it by Friday, please let me know"
        // Both lost a comma that is doing real grammatical work. And `\s`
        // spanned newlines, so a dictated line break was silently joined.
        // The ellipsis is written literally. `\u{2026}` is Swift's escape syntax,
        // not ICU's — inside a raw string it reaches the regex engine verbatim,
        // fails to compile, and the whole rule silently stops firing.
        let pattern = #"[ \t]*,[ \t]*(?=(?:"# + alternation
            + #")[ \t]*(?:[.!?…\n]|$))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let ns = NSMutableString(string: text)
        let replaced = regex.replaceMatches(
            in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: " "
        )
        // Removed nothing, so touch nothing. This used to fall through to
        // `collapseSpaces` unconditionally, which rewrote whitespace on EVERY
        // dictation the toggle was on for — flattening code indentation and
        // closing up " ; " and " : " in terminal text, with no comma involved.
        // That contradicts this file's own contract of only ever removing commas.
        guard replaced > 0 else { return text }
        return collapseSpaces(ns as String)
    }

    // MARK: - helpers

    private static func collapseSpaces(_ text: String) -> String {
        // Removing a comma can leave a double space. Only collapse runs that
        // FOLLOW visible text: a run at the start of a line is indentation, and
        // flattening it destroyed dictated code and numbered lists.
        let collapsed = text.replacingOccurrences(
            of: #"(?<=[^\n \t])[ \t]{2,}"#, with: " ", options: .regularExpression
        )
        // Only sentence-ending marks. `;` and `:` were in this class and closed
        // up " ; " and " : " in shell and config text ("cd /tmp ; ls" -> "cd
        // /tmp; ls", "3 : 4" -> "3: 4"), which is not this pass's business.
        return collapsed.replacingOccurrences(
            of: #" +([.!?])"#, with: "$1", options: .regularExpression
        )
    }
}
