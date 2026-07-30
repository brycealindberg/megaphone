import Foundation

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
/// Pure string logic, no AppKit, so the whole thing is unit-testable.
enum SelfCorrectionResolver {
    /// Phrases that mark "ignore what I just said". Multi-word entries first so
    /// the longest match wins.
    static let markers: [String] = [
        "no actually wait", "no scratch that", "scratch that",
        "let me start over", "let me restart", "let me redo that",
        "start over", "actually wait", "no wait", "wait no"
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
        let after = ns.substring(from: afterStart)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—-\t\n"))
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

    /// The index just after the previous sentence terminator (. ! ?) or newline
    /// before `location`, i.e. the start of the clause the marker sits in.
    static func sentenceStart(before location: Int, in ns: NSString) -> Int {
        var i = location - 1
        while i >= 0 {
            let c = ns.character(at: i)
            if let scalar = UnicodeScalar(c),
               scalar == "." || scalar == "!" || scalar == "?" || scalar == "\n" {
                // Skip the terminator and any following spaces.
                var start = i + 1
                while start < ns.length,
                      let s = UnicodeScalar(ns.character(at: start)),
                      CharacterSet.whitespaces.contains(s) {
                    start += 1
                }
                return start
            }
            i -= 1
        }
        return 0
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
