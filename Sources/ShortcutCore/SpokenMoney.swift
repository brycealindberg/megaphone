import Foundation

/// Writes a spoken amount as a currency figure: "it cost me over 40 dollars"
/// becomes "it cost me over $40".
///
/// Measured on 9,401 real dictations, then replayed through this pipeline's own
/// cleanup model. Of 28 transcripts carrying an explicit currency word, the
/// model formatted 6 and left 22 alone — the same inconsistency that motivated
/// `SpokenEmailAddress`, and the same reason the rule belongs in code.
///
/// ```
/// I've been charged 140 bucks          -> $140      model left it
/// it cost me over 40 dollars           -> $40       model left it
/// a budget of a hundred dollars total  -> $100      model left it
/// they proposed 2k for the build       -> $2,000    model already does this
/// ```
///
/// **Only an explicit currency noun triggers it.** That is the whole safety
/// argument: there is no reading of "140 bucks" that is not money. The far more
/// common spoken form in the same corpus — a bare "k" suffix, 56 of 85 cases —
/// is deliberately left to the model, because it is genuinely ambiguous and the
/// corpus proves it: "145k followers", "2k usable leads per day" and "25,000
/// credits" sit alongside "2k for the project". A deterministic pass cannot tell
/// those apart, so it does not try.
///
/// Three refusals are load-bearing, and every one of them is a real sentence
/// from the corpus rather than an invented edge case:
///
/// - **"a 200 pound stone"** is weight. Pounds and euros are not handled at all;
///   dollars and bucks have no such collision.
/// - **"multi-million dollar business"**, **"Million dollar sass"** are idioms.
///   `million` and `billion` are refused as amounts outright.
/// - **"Thirty-nine dollar a month plan"** is one number split by a hyphen.
///   Matching only the tail would write "Thirty-$9".
///
/// That last one is the general shape of the danger, and the first version of
/// this file got it wrong in every case the hyphen did not cover: "eighty five
/// bucks" became "eighty $5", a 17x error that still reads like a typo. So a
/// spoken amount is now parsed as a whole phrase — "twenty five hundred",
/// "two thousand five hundred", "a hundred and twenty" — or not at all.
///
/// Known limits, all deliberate:
/// - **Ranges** convert only the member carrying the noun: "20 to 30 dollars"
///   becomes "20 to $30". Fixing it would mean rewriting a number with no
///   currency noun attached, which is the one invariant everything above rests
///   on. Left alone on purpose.
/// - **"we saw two bucks in the field"** becomes "$2". Deer lose to freelance
///   pricing; there is no anchor that separates them.
enum SpokenMoney {
    /// Runs in `finishText` only, so by here the cleanup model has already had
    /// its turn and anything it formatted carries a "$" instead of the noun.
    static func format(_ text: String) -> String {
        guard text.range(of: #"(?i)(?<![\p{L}\p{N}])(?:dollars?|bucks?)(?![\p{L}\p{N}])"#,
                         options: .regularExpression) != nil else { return text }

        var tokens = tokenize(text)
        var index = tokens.count - 1
        // Right to left: an amount can run several tokens back from the currency
        // noun, and walking backwards keeps the indices ahead of it stable.
        while index >= 0 {
            guard let isPlural = currencyNoun(tokens[index].text), index > 0,
                  let amount = amount(in: tokens, endingAt: index - 1, plural: isPlural)
            else { index -= 1; continue }

            // Punctuation that bracketed the phrase belongs outside the figure:
            // "(20 bucks)" must not lose its opening parenthesis, and
            // "50 dollars." must keep its full stop.
            let text = leading(tokens[amount.startIndex].text)
                + format(amount.value, hasFraction: amount.hasFraction)
                + trailing(tokens[index].text)
            tokens.replaceSubrange(
                amount.startIndex...index,
                with: [Token(text: text, separator: tokens[index].separator)]
            )
            index = amount.startIndex - 1
        }
        return tokens.map { $0.text + $0.separator }.joined()
    }

    // MARK: Tokens

    /// A word and the whitespace that followed it, so rejoining is exact.
    ///
    /// Splitting on a literal " " instead loses every amount but the last one in
    /// multi-line output: "20 dollars\n- Cursor" makes "dollars\n-" a single
    /// token that matches nothing. That shape is reachable — the Smart path
    /// hands the model's own output straight to `finishText` without the
    /// whitespace collapse that `tidy` does, and the cleanup prompt asks the
    /// model to render spoken bullets as real list lines.
    private struct Token {
        var text: String
        var separator: String
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = Token(text: "", separator: "")
        var inSeparator = false
        for character in text {
            if character.isWhitespace {
                inSeparator = true
                current.separator.append(character)
            } else {
                if inSeparator {
                    tokens.append(current)
                    current = Token(text: "", separator: "")
                    inSeparator = false
                }
                current.text.append(character)
            }
        }
        tokens.append(current)
        return tokens
    }

    /// The currency noun, if this token is one.
    ///
    /// A capital letter disqualifies it: "three Dollar General stores" and "two
    /// Bucks games" are proper nouns, and a real amount never capitalises the
    /// noun mid-sentence. Sentence-initial "Dollars…" has no number before it,
    /// so nothing is lost by refusing the whole shape.
    /// Returns whether it is plural, or nil when the token is not one.
    private static func currencyNoun(_ token: String) -> Bool? {
        let core = core(token)
        guard core.first?.isUppercase != true else { return nil }
        // "twenty dollars' worth" is possessive, and the apostrophe has nowhere
        // to go once the noun is a figure — "$20' worth" is not text anyone
        // wants. Refusing leaves a perfectly good sentence alone.
        guard !trailing(token).contains(where: { $0 == "'" || $0 == "\u{2019}" }) else { return nil }
        switch core.lowercased() {
        case "dollar", "buck": return false
        case "dollars", "bucks": return true
        default: return nil
        }
    }

    // MARK: Amounts

    private struct Amount {
        let value: Decimal
        let hasFraction: Bool
        let startIndex: Int
    }

    /// The amount ending at `end`, and the first token it occupies.
    ///
    /// - Parameter plural: whether the currency noun was plural. It decides
    ///   whether a leading article belongs to the amount or to a following noun:
    ///   "a hundred dollars total" is "$100 total", but "a thousand dollar
    ///   retainer" is "a $1,000 retainer" — the article is the retainer's.
    private static func amount(in tokens: [Token], endingAt end: Int, plural: Bool) -> Amount? {
        // Digits are self-contained; never scan left from them. "for 2 hours 30
        // dollars" must not become one number.
        if let number = decimal(core(tokens[end].text)) {
            // "in 2020 dollars" is an inflation-adjusted figure, not $2,020.
            // Narrow on purpose: widening it to allow an intervening word would
            // also refuse "put in 2000 dollars", which is a real amount.
            if !number.hasFraction, end > 0, core(tokens[end - 1].text).lowercased() == "in",
               let integer = Int(exactly: NSDecimalNumber(decimal: number.value)),
               (1900...2099).contains(integer) { return nil }
            return Amount(value: number.value, hasFraction: number.hasFraction, startIndex: end)
        }

        // A spoken number phrase: collect the whole run, then evaluate it.
        var start = end
        while start >= 0, isPhraseWord(core(tokens[start].text)) {
            // A number phrase carries no internal sentence punctuation, so a
            // token that ends in some is the left wall: in "give me five, ten
            // dollars" the run is "ten", not "five ten".
            if start < end, endsSentencePart(tokens[start].text) { break }
            start -= 1
        }
        start += 1
        guard start <= end else { return nil }

        var words = tokens[start...end].map { core($0.text).lowercased() }
        // "and" and an article are only meaningful inside the phrase.
        while words.first == "and" { words.removeFirst(); start += 1 }
        while words.last == "and" || isArticle(words.last ?? "") { words.removeLast() }
        guard !words.isEmpty, start + words.count - 1 == end else { return nil }
        // An article is only a number when a scale follows it: "a hundred" is
        // 100, but a bare "a" is just an article.
        if isArticle(words[0]) {
            guard words.count > 1, scale(words[1]) != nil else { return nil }
            // The article stays with the following noun when the currency noun
            // is singular and therefore adjectival — "a $1,000 retainer". It
            // still counts as the "one" in "a thousand", so only the token range
            // moves, not the phrase being evaluated.
            if !plural { start += 1 }
        }
        // "a couple hundred dollars" and "several thousand dollars" are vague on
        // purpose. A bare scale otherwise means one of it, which would turn them
        // into exactly $100 and $1,000 — a precision the speaker avoided. The
        // signal is the word before the phrase, not the phrase itself:
        // "Claude Code's hundred dollar a month plan" really is $100.
        if start > 0, isVagueQuantifier(core(tokens[start - 1].text).lowercased()),
           smallNumber(words[0]) == nil { return nil }
        guard let value = evaluate(words) else { return nil }
        return Amount(value: Decimal(value), hasFraction: false, startIndex: start)
    }

    private static func isArticle(_ word: String) -> Bool { word == "a" || word == "an" }

    /// Words that make a following amount an estimate rather than a figure.
    private static func isVagueQuantifier(_ word: String) -> Bool {
        ["couple", "few", "several", "many", "some", "dozen", "dozens"].contains(word)
    }

    private static func isPhraseWord(_ token: String) -> Bool {
        let word = token.lowercased()
        return smallNumber(word) != nil || scale(word) != nil || word == "and" || isArticle(word)
    }

    /// Standard English cardinal accumulation, which is what makes "twenty five
    /// hundred" 2,500 rather than 20 and 500.
    private static func evaluate(_ words: [String]) -> Int? {
        var total = 0, current = 0, sawNumber = false
        for word in words {
            if word == "and" { continue }
            if isArticle(word) { current += 1; sawNumber = true; continue }
            if let small = smallNumber(word) { current += small; sawNumber = true; continue }
            guard let scale = scale(word) else { return nil }
            sawNumber = true
            // A bare scale means one of it: "a hundred dollar plan" is $100.
            if scale == 100 {
                current = max(current, 1) * 100
            } else {
                total += max(current, 1) * scale
                current = 0
            }
        }
        guard sawNumber else { return nil }
        return total + current
    }

    /// `million` and `billion` are deliberately absent — in this corpus they only
    /// ever appear adjectivally ("multi-million dollar business").
    private static func scale(_ word: String) -> Int? {
        switch word {
        case "hundred": return 100
        case "thousand": return 1_000
        default: return nil
        }
    }

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// 0–99, including the hyphenated compounds dictation produces as one token.
    private static func smallNumber(_ word: String) -> Int? {
        if let unit = units[word] { return unit }
        if let ten = tens[word] { return ten }
        let parts = word.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let ten = tens[String(parts[0])],
              let unit = units[String(parts[1])], (1...9).contains(unit) else { return nil }
        return ten + unit
    }

    /// A written number: "500", "25,000", "3.50".
    ///
    /// Grouping is validated rather than stripped, so the European "3,50" is
    /// refused instead of silently becoming 350; and a leading zero means a
    /// reference number, not a price.
    private static func decimal(_ token: String) -> (value: Decimal, hasFraction: Bool)? {
        guard !token.isEmpty else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        var fraction = ""
        if parts.count == 2 {
            fraction = String(parts[1])
            guard (1...2).contains(fraction.count), fraction.allSatisfy(\.isASCII),
                  fraction.allSatisfy(\.isNumber) else { return nil }
        }

        let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
        guard let first = groups.first, !first.isEmpty else { return nil }
        for (offset, group) in groups.enumerated() {
            let expected = offset == 0 ? 1...3 : 3...3
            guard expected.contains(group.count), group.allSatisfy(\.isASCII),
                  group.allSatisfy(\.isNumber) else { return nil }
        }
        let integer = groups.joined()
        guard integer.count == 1 || integer.first != "0" else { return nil }

        let literal = fraction.isEmpty ? integer : integer + "." + fraction
        guard let value = Decimal(string: literal, locale: nil) else { return nil }
        return (value, !fraction.isEmpty)
    }

    // MARK: Formatting

    private static let grouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        // Set outright rather than inherited from a locale. The corpus reads
        // "$10,000" and "$1,500", and the "$" is fixed, so the separator has to
        // be too — `en_US_POSIX` in particular does no grouping at all and
        // silently produced "$1000".
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        return formatter
    }()

    private static func format(_ value: Decimal, hasFraction: Bool) -> String {
        grouping.minimumFractionDigits = hasFraction ? 2 : 0
        grouping.maximumFractionDigits = hasFraction ? 2 : 0
        let number = NSDecimalNumber(decimal: value)
        return "$" + (grouping.string(from: number) ?? number.stringValue)
    }

    // MARK: Punctuation

    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'“”‘’()[]{}")

    private static func core(_ token: String) -> String {
        token.trimmingCharacters(in: edgePunctuation)
    }

    private static func endsSentencePart(_ token: String) -> Bool {
        guard let last = token.unicodeScalars.last else { return false }
        return edgePunctuation.contains(last)
    }

    /// Punctuation that opened a token and must survive the rewrite.
    private static func leading(_ token: String) -> String {
        String(token.prefix(while: { $0.unicodeScalars.allSatisfy(edgePunctuation.contains) }))
    }

    /// Punctuation that trailed a token and must survive the rewrite.
    private static func trailing(_ token: String) -> String {
        String(token.suffix(while: { $0.unicodeScalars.allSatisfy(edgePunctuation.contains) }))
    }
}

private extension StringProtocol {
    /// Mirror of `prefix(while:)` taken from the end.
    func suffix(while predicate: (Element) -> Bool) -> SubSequence {
        var index = endIndex
        while index > startIndex {
            let previous = self.index(before: index)
            guard predicate(self[previous]) else { break }
            index = previous
        }
        return self[index...]
    }
}
