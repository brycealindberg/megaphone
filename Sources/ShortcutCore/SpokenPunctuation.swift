import Foundation

/// Settles a spoken punctuation word — "exclamation mark" — into the mark
/// itself, *before* the cleanup model runs.
///
/// The user's correction list already contains `exclamation mark -> !`, but
/// corrections are applied to the model's **output**, and the model deletes the
/// words first: it reads a trailing "exclamation mark" as abandoned wording,
/// exactly as it reads a trailing "crying face emoji" that way. Measured
/// 2026-08-05 from a real dictation:
///
///     spoken "…and that you traveled safe. exclamation mark"
///     model  "…and that you traveled safe."
///     shipped the same — no "!" anywhere, the instruction silently dropped.
///
/// This is the same argument, and the same fix, as `LaughterSpelling` and
/// `SpokenEmoji`: a post-step cannot rescue text that is already gone, so hand
/// the model the mark instead of the words and it has no reason to touch it.
///
/// ## Why this needs more than a string replacement
///
/// Substituting in place leaves `"traveled safe. !"` — the recogniser has
/// already ended the sentence, and the mark arrives as a separate token after
/// it. The mark has to absorb that terminator and close up against the word, or
/// the "fix" ships punctuation the speaker plainly did not dictate.
///
/// Only mappings whose replacement is **entirely punctuation** are handled here.
/// Everything else stays in the normal correction pass, where measuring showed
/// it belongs (handing the model corrected spellings scored materially worse).
enum SpokenPunctuation {
    /// The mappings this pass owns: replacement is non-empty and contains no
    /// letters or digits. `et cetera -> etc.` therefore stays behind, because
    /// "etc." is a word the model has no urge to delete.
    static func punctuationMappings(
        _ corrections: [TranscriptTidier.CorrectionMapping]
    ) -> [TranscriptTidier.CorrectionMapping] {
        corrections.filter { mapping in
            !mapping.replacement.isEmpty
                && mapping.replacement.allSatisfy { !$0.isLetter && !$0.isNumber }
        }
    }

    /// Idempotent: once the words are a mark, there is nothing left to match, so
    /// `finishText` re-running this on the way out is a no-op.
    static func settle(
        _ text: String,
        corrections: [TranscriptTidier.CorrectionMapping]
    ) -> String {
        let mappings = punctuationMappings(corrections)
        guard !mappings.isEmpty, !text.isEmpty else { return text }

        var result = text
        for mapping in mappings.sorted(by: { $0.spoken.count > $1.spoken.count }) {
            let spoken = mapping.spoken
                .split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
            // Swallow the recogniser's own punctuation on BOTH sides, so the mark
            // lands directly on the preceding word. Measured over 9,804 real
            // dictations, where this phrase appears 196 times and almost never
            // bare — it arrives wrapped in the pauses around it:
            //
            //     "It will, exclamation mark."        -> "It will!"
            //     "let you know, exclamation mark, hope" -> "let you know! hope"
            //     "Got it. Exclamation mark."         -> "Got it!"
            //
            // A leading comma matters as much as a full stop: absorbing only
            // terminators left "It will,! ." Trailing marks are absorbed because
            // the dictated mark IS the sentence's punctuation now.
            let pattern = #"[ \t]*(?:[,.!?;:]+[ \t]*)?(?<![\p{L}\p{M}\p{N}_])"# + spoken
                + #"(?![\p{L}\p{M}\p{N}_])[ \t]*[,.!?;:]*[ \t]*"#
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]
            ) else { continue }
            let ns = NSMutableString(string: result)
            let matches = regex.matches(
                in: result, range: NSRange(location: 0, length: ns.length)
            )
            for match in matches.reversed() {
                let end = match.range.location + match.range.length
                let atEnd = end >= ns.length
                    || CharacterSet.newlines.contains(
                        UnicodeScalar(ns.character(at: end)) ?? " "
                    )
                ns.replaceCharacters(
                    in: match.range,
                    with: atEnd ? mapping.replacement : mapping.replacement + " "
                )
            }
            result = ns as String
        }
        // "I appreciate it, exclamation mark, exclamation mark." leaves "it! !":
        // the first match cannot see that a second mark follows, because at that
        // point the text between them is still the spoken words. A space between
        // two punctuation marks is never wanted, so close them up at the end.
        if let regex = try? NSRegularExpression(pattern: #"(?<=[,.!?;:])[ \t]+(?=[,.!?;:])"#) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: ""
            )
        }
        return result
    }
}
