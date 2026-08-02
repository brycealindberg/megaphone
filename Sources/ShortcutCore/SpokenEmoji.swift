import Foundation

/// Turns a spoken description into the emoji it describes: "laughing face
/// emoji" becomes 😂, "rocket emoji" becomes 🚀.
///
/// The word "emoji" is a required trigger. Without it this pass does nothing at
/// all, so ordinary dictation ("she gave me a red heart") is never rewritten —
/// an emoji only ever appears because the speaker asked for one out loud. That
/// single rule is what keeps a substitution pass safe enough to run everywhere.
///
/// Names resolve in two tiers:
///
///  1. `aliases` — what people actually say. Every entry here is a name the
///     Unicode table cannot answer, either because the emoji is only named in
///     CLDR ("pleading face") or because its Unicode name is a relic nobody
///     speaks ("person raising both hands in celebration" for 🙌).
///  2. The Unicode name table itself, via ICU. That covers roughly 3,700 emoji
///     for free — "rocket", "brain", "goat", "crescent moon" — so the alias
///     list only has to carry the gaps rather than the whole catalogue.
enum SpokenEmoji {
    /// Longest spoken name considered, in words. Six, because the real names
    /// run long — "rolling on the floor laughing", "smiling face with
    /// heart-shaped eyes", "person raising both hands in celebration". A wide
    /// window costs nothing in false positives: a phrase is only ever consumed
    /// if it resolves to an actual emoji, and the longest candidate is tried
    /// first so a shorter name inside it can never win by accident.
    static let maxNameWords = 6

    /// Spoken name -> emoji, for the names ICU cannot resolve. Keys are lower
    /// case and matched exactly; add a spelling variant as its own key rather
    /// than trying to normalise at match time.
    static let aliases: [String: String] = [
        // laughter and smiles
        "laughing": "😂", "laughing face": "😂", "crying laughing": "😂",
        "tears of joy": "😂", "lol": "😂", "laugh": "😂",
        "rofl": "🤣", "rolling on the floor laughing": "🤣", "dying laughing": "🤣",
        "smiley": "😊", "smiley face": "😊", "smiling face": "😊", "happy face": "😊",
        "happy": "😊", "smile": "😊",
        "sweat smile": "😅", "nervous laugh": "😅",
        "upside down face": "🙃", "upside down": "🙃",
        "heart eyes": "😍", "love eyes": "😍",
        "sunglasses": "😎", "cool face": "😎",
        "star struck": "🤩", "starstruck": "🤩",
        "rolling eyes": "🙄", "eye roll": "🙄",
        "sobbing": "😭", "bawling": "😭",
        "pleading face": "🥺", "pleading": "🥺", "puppy eyes": "🥺",
        "screaming face": "😱", "screaming": "😱",
        "exploding head": "🤯", "mind blown": "🤯",
        "facepalm": "🤦", "face palm": "🤦",
        "partying face": "🥳", "party face": "🥳",
        "hot face": "🥵", "cold face": "🥶",
        "sad face": "😢", "sad": "😢",

        // hands
        "thumbs up": "👍", "thumbs down": "👎",
        "clapping hands": "👏", "clapping": "👏", "clap": "👏", "applause": "👏",
        "waving hand": "👋", "waving": "👋", "wave": "👋",
        "folded hands": "🙏", "praying hands": "🙏", "prayer hands": "🙏", "praying": "🙏",
        "ok hand": "👌", "okay hand": "👌",
        "raised hands": "🙌", "hands up": "🙌",
        "oncoming fist": "👊", "fist bump": "👊", "fist": "👊",
        "crossed fingers": "🤞", "fingers crossed": "🤞",
        "muscle": "💪", "flex": "💪",
        "peace sign": "✌️", "peace": "✌️",

        // symbols people ask for by name
        "red heart": "❤️", "heart": "❤️",
        "hundred points": "💯", "hundred": "💯", "one hundred": "💯",
        "check mark button": "✅", "check mark": "✅", "checkmark": "✅",
        "check": "✅", "tick": "✅", "green check": "✅",
        "red x": "❌", "cross": "❌",
        "star": "⭐",
        "light bulb": "💡", "lightbulb": "💡", "idea": "💡",
        "chart increasing": "📈", "chart up": "📈", "graph up": "📈",
        "collision": "💥", "explosion": "💥", "boom": "💥",
        "high voltage": "⚡", "lightning": "⚡", "lightning bolt": "⚡",
        "red circle": "🔴", "green circle": "🟢",
        "triangular flag": "🚩", "red flag": "🚩",
        "magnifying glass": "🔍", "search": "🔍",
        "wrapped gift": "🎁", "gift": "🎁", "present": "🎁",
        "party": "🎉", "tada": "🎉", "confetti": "🎉", "celebration": "🎉",

        // things
        "pizza": "🍕", "sun": "☀️", "unicorn": "🦄", "alien": "👽",
        "robot": "🤖", "house": "🏠", "home": "🏠"
    ]

    /// A spoken name and the emoji it means, alias first, then the Unicode name
    /// table. Returns nil for anything that is not a name at all, which is what
    /// leaves "add an emoji" untouched.
    static func emoji(for spokenName: String) -> String? {
        let name = spokenName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !name.isEmpty else { return nil }
        if let alias = aliases[name] { return alias }
        return unicodeNamed(name)
    }

    /// ICU's `Name-Any` transform, run in reverse over `\N{THE NAME}`.
    ///
    /// Guarded three ways, because that table also holds every letter and
    /// control character: the result must be a single scalar, non-ASCII (so
    /// "\N{DIGIT ONE}" style hits can never leak through), and actually flagged
    /// as emoji. Scalars that default to text presentation get the U+FE0F
    /// selector appended, so "warning sign emoji" pastes as ⚠️ and not ⚠.
    private static func unicodeNamed(_ name: String) -> String? {
        let escaped = "\\N{\(name.uppercased())}"
        guard let resolved = escaped.applyingTransform(.toUnicodeName, reverse: true),
              resolved != escaped,
              resolved.unicodeScalars.count == 1,
              let scalar = resolved.unicodeScalars.first,
              !scalar.isASCII,
              scalar.properties.isEmoji
        else { return nil }
        return scalar.properties.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}"
    }

    // MARK: - substitution

    /// The trigger word with up to `maxNameWords` plain words in front of it.
    /// The name characters deliberately exclude punctuation, so a comma or a
    /// full stop ends the phrase: "that's sad, emoji" cannot reach back past
    /// the comma to find a name.
    ///
    /// The word repeat is lazy, so each match stops at the *first* trigger it
    /// can reach. Greedy, it would happily treat an earlier "emoji" as one of
    /// the name words and swallow it: "fire emoji and rocket emoji" matched as
    /// a single phrase, and only the rocket came out.
    /// Name words are separated by whitespace only — never a comma.
    ///
    /// Tried 2026-08-01 and reverted: allowing a comma would let the recogniser's
    /// "Sounds good thumbs up, emoji, see you tomorrow." resolve, which it
    /// currently does not. But it also turns the ordinary sentence "that's sad,
    /// emoji" into "that's 😢", because "sad" is an alias. A comma before the
    /// trigger is genuinely ambiguous between a spoken name and a sentence that
    /// merely ends near the word, and silently rewriting real prose is the worse
    /// failure. `testDoesNotReachPastPunctuation` guards this.
    private static let phrasePattern =
        #"(?<![\p{L}\p{M}\p{N}_])((?:[\p{L}\p{N}'’-]+[ \t]+){0,6}?)(emojis?)(?![\p{L}\p{M}\p{N}_])"#

    private static let wordPattern = #"[\p{L}\p{N}'’-]+"#

    static func substitute(_ text: String) -> String {
        // Two steps, because they have different triggers. The phrase swap needs
        // the spoken word "emoji" to still be present; the punctuation tidy needs
        // only a glyph, so it also runs on the model's output where the trigger
        // word is long gone.
        tidyPunctuation(around: replacePhrases(in: text))
    }

    /// Strips the punctuation the recogniser hangs off a spoken emoji name.
    ///
    /// "thanks so much folded hands emoji" comes back from the recogniser as
    /// "Thanks so much, folded hands emoji." — it heard the pause before the
    /// name as a comma and closed the sentence after it. Replacing only the
    /// words left both marks stranded against the glyph: "Thanks so much, 🙏."
    /// Neither mark is punctuation the speaker asked for.
    ///
    /// A trailing mark is only removed at the very end of the text. Mid-sentence
    /// ("sounds good 👍, see you tomorrow") the comma is real and stays, and "!"
    /// and "?" are never removed anywhere because they carry meaning.
    /// True for a character that renders as an emoji.
    ///
    /// `isEmojiPresentation` alone is not enough and fails silently: ❤️ is
    /// U+2764 plus U+FE0F, and U+2764's presentation property is *false* because
    /// it defaults to text form. Checking only that property skipped every
    /// variation-selector emoji — ❤️ ⚠️ ✏️ — which is how "Heart emoji." shipped
    /// still producing "❤️." after this pass was supposedly fixed. Found in a
    /// real dictation, not in a test: every glyph in the tests (😂 🙏 🚀 😢)
    /// happens to be presentation-form.
    static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation || character.unicodeScalars.contains("\u{FE0F}")
    }

    /// Deliberately not a regex. `\p{Extended_Pictographic}` matches the *scalar*
    /// U+2764, so in "❤️." the U+FE0F sits between the match and the full stop
    /// and the pattern never reaches the punctuation — the first version of this
    /// function was a regex and left Bryce's real "❤️." untouched. Working in
    /// `Character`s means a grapheme cluster is one unit, however many scalars,
    /// so skin tones and ZWJ sequences come along for free.
    static func tidyPunctuation(around text: String) -> String {
        guard text.contains(where: isEmoji) else { return text }
        var characters = Array(text)

        // A trailing "." or "," at the very end, when an emoji is what precedes
        // it. Mid-sentence punctuation is real and is left alone, as are "!"
        // and "?" anywhere.
        var end = characters.count
        while end > 0, characters[end - 1] == " " || characters[end - 1] == "\t" { end -= 1 }
        var afterMarks = end
        while afterMarks > 0, characters[afterMarks - 1] == "." || characters[afterMarks - 1] == "," {
            afterMarks -= 1
        }
        if afterMarks < end, afterMarks > 0, isEmoji(characters[afterMarks - 1]) {
            characters.removeSubrange(afterMarks...)
        }

        // A comma the recogniser inserted where the speaker paused before naming
        // the emoji: "Thanks so much, 🙏" is one phrase, not a list.
        var result: [Character] = []
        var index = 0
        while index < characters.count {
            if characters[index] == "," {
                var lookahead = index + 1
                while lookahead < characters.count,
                      characters[lookahead] == " " || characters[lookahead] == "\t" {
                    lookahead += 1
                }
                if lookahead < characters.count, isEmoji(characters[lookahead]) {
                    if !result.isEmpty { result.append(" ") }
                    index = lookahead
                    continue
                }
            }
            result.append(characters[index])
            index += 1
        }
        return String(result)
    }

    private static func replacePhrases(in text: String) -> String {
        // Cheap exit for the overwhelmingly common case of a dictation that
        // never says "emoji" at all.
        guard text.range(
            of: #"(?<![\p{L}\p{M}\p{N}_])emojis?(?![\p{L}\p{M}\p{N}_])"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else { return text }

        guard let regex = try? NSRegularExpression(pattern: phrasePattern, options: [.caseInsensitive]),
              let words = try? NSRegularExpression(pattern: wordPattern)
        else { return text }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let nameArea = match.range(at: 1)
            guard nameArea.location != NSNotFound, nameArea.length > 0 else { continue }
            let candidateWords = words.matches(
                in: text, range: nameArea
            ).map { (range: $0.range, text: ns.substring(with: $0.range)) }
            guard !candidateWords.isEmpty else { continue }

            // Longest name first, so "laughing face" beats "face".
            let usable = candidateWords.suffix(maxNameWords)
            for start in usable.indices {
                let phrase = usable[start...].map(\.text).joined(separator: " ")
                guard let glyph = emoji(for: phrase) else { continue }
                let from = usable[start].range.location
                let through = match.range.location + match.range.length
                result.replaceCharacters(
                    in: NSRange(location: from, length: through - from), with: glyph
                )
                break
            }
        }
        return result as String
    }
}
