import Foundation
import NaturalLanguage

/// Resolves a mid-utterance restart — "let's meet at the office, no wait, let's
/// do it over Zoom" becomes "let's do it over Zoom" — which is the one
/// self-correction the on-device cleanup model will not do. It resolves
/// value-level swaps ("Thursday, no actually, Wednesday") but leaves the
/// abandoned clause of a restart in place, so this fills that gap.
///
/// The danger is treating a value swap as a restart and deleting the sentence
/// around it. The guard against that is strict: a restart is recognised only
/// when the text AFTER the marker begins a fresh parallel clause ("let's…",
/// "I'll…", "let me…"). A value swap's continuation is a bare word ("Wednesday"),
/// which never matches an opener, so those pass through untouched to the model.
///
/// No AppKit, so the whole thing is unit-testable. `NLTokenizer` is used for
/// sentence segmentation because scanning back for a `.` cuts inside decimals
/// and abbreviations.
enum SelfCorrectionResolver {
    /// Phrases that mark "ignore what I just said". Multi-word entries first so
    /// the longest match wins.
    static let markers: [String] = [
        "no actually wait", "no scratch that", "scratch that",
        "let me start over", "let me restart", "let me redo that",
        "start over", "actually wait", "no wait", "wait no", "i mean"
    ]

    /// Markers that abandon what came before even with **nothing after them**.
    ///
    /// The restart path below needs a re-stated clause to keep; these need
    /// nothing, because "…, actually scratch that." is a complete instruction on
    /// its own. Measured 2026-08-05 from a real dictation: `ScratchCommandMatcher`
    /// declined it (that command must be the whole utterance), this resolver
    /// declined it (nothing followed the marker), and the cleanup model left it
    /// alone (it resolves value swaps, not trailing abandonment) — so the text
    /// pasted verbatim and the speaker got nothing they asked for.
    ///
    /// Deliberately a **subset** of `markers`. "i mean", "no wait" and
    /// "actually wait" are excluded: "Let's meet Thursday, I mean." is a person
    /// trailing off, not deleting a sentence, and this path deletes sentences.
    static let trailingAbandonMarkers: Set<String> = [
        "scratch that", "no scratch that",
        "start over", "let me start over", "let me restart", "let me redo that"
    ]

    /// What has to sit immediately before a trailing marker for it to count as
    /// abandonment rather than the speaker's actual words. Without this,
    /// "I need to scratch that" loses the sentence it is the point of.
    ///
    /// A particle is enough on its own, with or without the comma, because the
    /// recogniser's comma placement is not reliable enough to require —
    /// separately measured this session at 190 commas against 43 in ground truth.
    private static let boundaryParticles: Set<String> = [
        "actually", "no", "ok", "okay", "um", "uh", "er", "hmm"
    ]

    /// A restart fires only when what follows the marker begins with one of
    /// these clause openers — the signal that the speaker is re-stating the
    /// whole thought, not correcting one word in it. Longest first.
    static let restartOpeners: [String] = [
        "i think we should", "why don't we", "how about we", "how about",
        "actually let's", "actually let me", "let's just", "let me just",
        "we should just", "we should", "we could", "we can", "we'll", "we will",
        "let's", "lets", "let me", "i'll", "i will", "i'm gonna", "i'm going to"
    ]

    static func resolve(_ text: String) -> String {
        let ns = text as NSString
        guard let marker = lastMarkerRange(in: text) else { return text }

        let afterStart = marker.location + marker.length
        guard afterStart <= ns.length else { return text }
        let tail = ns.substring(from: afterStart)

        // Nothing but punctuation left, so there is no re-stated clause to keep
        // and the restart path below cannot apply. Trimmed against punctuation
        // as well as whitespace: the recogniser writes "scratch that." with a
        // full stop, and testing `after` alone read that stop as a continuation.
        if tail.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        ).isEmpty {
            return resolvingTrailingAbandon(text, ns: ns, marker: marker)
        }

        // The marker ENDS ITS OWN SENTENCE and the speaker kept going:
        // "Okay scratch that. Okay I did it." Measured 2026-08-05 — this is what
        // Bryce actually does, and the first version of this only handled the
        // marker ending the whole dictation, so it did nothing here.
        //
        // A full stop is what separates this from a value swap. "Thursday, I
        // mean Wednesday" never puts a terminator between the marker and the
        // correction, so those still fall through to the opener gate below.
        if startsANewSentence(tail) {
            return resolvingTrailingAbandon(text, ns: ns, marker: marker)
        }

        let after = tail.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—-\t\n"))
        guard !after.isEmpty, beginsWithRestartOpener(after) else { return text }

        // Drop from the start of the current sentence (or the utterance) up to
        // and including the marker; keep earlier sentences and the restart.
        let clauseStart = sentenceStart(before: marker.location, in: ns)
        let prefix = ns.substring(to: clauseStart)
        // The kept clause always becomes a sentence start — either the whole
        // utterance, or right after the preserved earlier sentence — so it is
        // always capitalized.
        let joined = prefix + capitalizeFirst(after)
        return normalizeSpacing(joined)
    }

    // MARK: - trailing abandonment

    /// Drops the sentence the marker sits in, keeping every sentence the speaker
    /// finished before it. "Send the invoice Friday. OK I'm dictating now,
    /// actually scratch that." keeps "Send the invoice Friday."
    ///
    /// Keeping the earlier sentences is the whole safety margin here. This path
    /// deletes text on a lexical signal, which is the failure mode that sank
    /// five designs of the content-loss guard this same session, so it is scoped
    /// so that a misfire can only ever lose the clause the marker is attached to
    /// — never something the speaker had already finished saying. `lastTranscript`
    /// still holds the raw text for Paste Again either way.
    private static func resolvingTrailingAbandon(
        _ text: String, ns: NSString, marker: NSRange
    ) -> String {
        // `lastMarkerRange` returns the RIGHTMOST match, so "let me start over"
        // arrives as the shorter "start over" nested inside it — and the
        // boundary check then reads the text before it as "…let me" and
        // declines. Re-widen to the longest abandon phrase ending at the same
        // point before deciding anything.
        guard let phrase = longestTrailingAbandonRange(
            endingAt: marker.location + marker.length, in: ns
        ) else { return text }
        guard endsAtClauseBoundary(ns.substring(to: phrase.location)) else { return text }
        let kept = ns.substring(to: sentenceStart(before: phrase.location, in: ns))
        // Anything the speaker said AFTER the abandoned sentence is theirs and
        // survives: only the marker's own sentence is dropped. Skips the marker's
        // terminator and the space behind it.
        var resume = phrase.location + phrase.length
        while resume < ns.length,
              let s = UnicodeScalar(ns.character(at: resume)),
              CharacterSet.whitespacesAndNewlines.contains(s)
                || CharacterSet.punctuationCharacters.contains(s) {
            resume += 1
        }
        let tail = resume < ns.length ? ns.substring(from: resume) : ""
        guard !tail.isEmpty else { return normalizeSpacing(kept) }
        return normalizeSpacing(kept.isEmpty ? capitalizeFirst(tail) : kept + " " + tail)
    }

    /// Whether the text right after a marker is a single sentence terminator
    /// followed by a genuinely new sentence.
    ///
    /// All three conditions carry weight:
    ///   - **exactly one** terminator, so an ellipsis does not qualify.
    ///     "Actually, let me start over... and continue" is one sentence with a
    ///     pause in it, and dropping its first half loses what the speaker said.
    ///   - a **capital** afterwards, the other half of that same guard: the
    ///     recogniser capitalises sentence starts, and "... and continue" does
    ///     not get one.
    ///   - a terminator at all, which is what separates this from a value swap:
    ///     "Thursday, I mean Wednesday" never puts a full stop between the
    ///     marker and the correction.
    private static func startsANewSentence(_ tail: String) -> Bool {
        var rest = Substring(tail).drop(while: { $0.isWhitespace })
        guard let terminator = rest.first,
              terminator == "." || terminator == "!" || terminator == "?" else { return false }
        rest = rest.dropFirst()
        if let next = rest.first, next == "." || next == "!" || next == "?" { return false }
        rest = rest.drop(while: { $0.isWhitespace })
        guard let opener = rest.first else { return false }
        return opener.isUppercase
    }

    /// The longest `trailingAbandonMarkers` phrase whose match ends exactly at
    /// `end`, or nil when the marker there is not an abandon phrase at all.
    private static func longestTrailingAbandonRange(endingAt end: Int, in ns: NSString) -> NSRange? {
        var best: NSRange?
        for phrase in trailingAbandonMarkers {
            let pattern = #"(?<![\p{L}\p{N}])"# + escapedSpaced(phrase) + #"(?![\p{L}\p{N}])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let all = regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
            for match in all where match.range.location + match.range.length == end {
                if best == nil || match.range.length > best!.length { best = match.range }
            }
        }
        return best
    }

    /// Whether the text before a trailing marker ends somewhere a new clause
    /// could start — a particle ("actually"), clause punctuation, a finished
    /// sentence, or the very beginning of the utterance.
    ///
    /// This is the check that keeps "I need to scratch that" intact: "to" is
    /// neither a particle nor punctuation, so the marker is part of the sentence
    /// rather than a comment on it.
    private static func endsAtClauseBoundary(_ before: String) -> Bool {
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        if last == "," || last == ";" || last == ":" || last == "—" || last == "-"
            || last == "." || last == "!" || last == "?" { return true }
        let lastWord = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .last
            .map { String($0).lowercased().filter { !$0.isPunctuation } } ?? ""
        return boundaryParticles.contains(lastWord)
    }

    // MARK: - marker

    /// The rightmost marker, so a chain of restarts collapses to the final one.
    /// A marker only counts on word boundaries, so "waitno" or "startover" as
    /// part of a longer word does not match.
    static func lastMarkerRange(in text: String) -> NSRange? {
        let ns = text as NSString
        var best: NSRange?
        for marker in markers {
            let pattern = #"(?<![\p{L}\p{N}])"# + escapedSpaced(marker) + #"(?![\p{L}\p{N}])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last?.range else { continue }
            if best == nil || last.location > best!.location {
                best = last
            }
        }
        return best
    }

    static func beginsWithRestartOpener(_ text: String) -> Bool {
        let lower = text.lowercased()
        for opener in restartOpeners {
            if lower == opener { return true }
            if lower.hasPrefix(opener) {
                // The opener must be a whole word, not a prefix of a longer one:
                // "lets" must not match "letsomeone". Next char is a boundary.
                let idx = lower.index(lower.startIndex, offsetBy: opener.count)
                let next = lower[idx]
                if next == " " || next == "'" || next == "," { return true }
            }
        }
        return false
    }

    // MARK: - boundaries

    /// The start of the sentence containing `location`.
    ///
    /// Uses `NLTokenizer` rather than scanning back for a `.`, because scanning
    /// treats every period as terminal and so cuts inside decimals and
    /// abbreviations. That produced a *corrupted fragment*, which is worse than
    /// either possible correct answer:
    ///
    ///     "Charge 1.5 million, actually scratch that."  ->  "Charge 1."
    ///     "Tell Dr. Smith tomorrow, scratch that."      ->  "Tell Dr."
    ///
    /// Newlines are still honoured directly: the tokenizer does not always treat
    /// a hard break as a sentence boundary, and dictated line breaks are one.
    static func sentenceStart(before location: Int, in ns: NSString) -> Int {
        guard location > 0 else { return 0 }
        var start = 0
        let text = ns as String
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // NSRange(_:in:) converts to UTF-16 offsets, which is what NSString
            // indices are. `text.distance` counts Characters and would drift on
            // any emoji or combining mark.
            // `<=`, not `<`: when the marker IS the start of its own sentence
            // ("Charge 1.5 million. Scratch that."), that sentence is still the
            // one containing it. With `<` the scan stopped at the previous
            // sentence, returned 0, and dropped the earlier sentence too —
            // destroying the guarantee that only the marker's own clause is lost.
            let begin = NSRange(range, in: text).location
            if begin <= location { start = begin; return true }
            return false
        }
        // A hard line break after the tokenizer's sentence start still opens a
        // new clause, so take whichever boundary is closer to the marker.
        var i = location - 1
        while i >= start {
            if let scalar = UnicodeScalar(ns.character(at: i)), scalar == "\n" {
                start = i + 1
                break
            }
            i -= 1
        }
        while start < ns.length,
              let s = UnicodeScalar(ns.character(at: start)),
              CharacterSet.whitespaces.contains(s) {
            start += 1
        }
        return min(start, location)
    }

    // MARK: - helpers

    private static func escapedSpaced(_ phrase: String) -> String {
        phrase
            .split(separator: " ")
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    private static func normalizeSpacing(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" +([.,!?;:])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
