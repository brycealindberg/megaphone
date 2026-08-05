import Foundation

/// The pure half of `AppContextService.selectTextImmediatelyBeforeCaret`:
/// frame the accessibility read, then decide what to select from what came back.
///
/// Split out because the other half needs a live accessibility element and so
/// cannot be unit-tested at all, while *this* is where every off-by-one lives —
/// and the caller's next move is to paste over whatever range comes back, in the
/// user's real document. It was untested while fused to the I/O.
///
/// Both the framing (`windowRange`) and the validation (`evaluate`) live here
/// rather than at the call site, so the tests exercise the real arithmetic
/// instead of a copy of it that can silently drift.
enum CaretPrecedingSelection {
    /// What a ranged read turned out to be worth.
    enum Outcome: Equatable {
        /// The response did not answer the request — re-read the whole value.
        case invalidRead
        /// The window is trustworthy and the target is not in front of the caret.
        /// Definitive: `windowRange` covers every character a match could use.
        case noMatch
        /// Select this range, in the element's own coordinates.
        case selection(NSRange)
    }

    /// The characters to ask the element for: exactly those a match could
    /// involve, ending at the caret. Nil when no useful read exists.
    ///
    /// The `+ 1` is the convenience space dictation may have appended after
    /// sentence punctuation, which `evaluate` steps back over.
    static func windowRange(target: String, caret: Int) -> NSRange? {
        let targetLength = (target as NSString).length
        guard targetLength > 0, caret >= targetLength else { return nil }
        let start = max(0, caret - (targetLength + 1))
        let length = caret - start
        guard length > 0 else { return nil }
        return NSRange(location: start, length: length)
    }

    /// Validate a ranged read against the request it answered, then decide.
    ///
    /// The length check is the load-bearing one. An element that clamps a range
    /// answers `.success` with a SHORT string; mapping that back through the
    /// *requested* start would shift every offset and select text the user never
    /// dictated — e.g. a read of "hello" that actually came from offsets 5-10
    /// being credited to the requested start of 4, overwriting 4-9. A response
    /// that does not answer the request is not evidence about the document.
    static func evaluate(target: String, window: NSString, requested: NSRange) -> Outcome {
        guard requested.location >= 0, window.length == requested.length else {
            return .invalidRead
        }
        guard let range = selectionRange(
            matching: target,
            endingAt: window,
            windowStart: requested.location
        ) else { return .noMatch }
        return .selection(range)
    }

    /// The range to select given text ending exactly at the caret, or nil.
    ///
    /// `windowStart` is the absolute index of `window`'s first character, so a
    /// caller may hand over the element's whole value (`windowStart: 0`) or a
    /// ranged read of just the tail, and get absolute coordinates back either way.
    static func selectionRange(
        matching target: String,
        endingAt window: NSString,
        windowStart: Int
    ) -> NSRange? {
        let targetLength = (target as NSString).length
        guard targetLength > 0, windowStart >= 0 else { return nil }

        // Dictation appends one convenience space after sentence punctuation.
        var caret = window.length
        if caret > 0,
           let trailingScalar = UnicodeScalar(window.character(at: caret - 1)),
           CharacterSet.whitespacesAndNewlines.contains(trailingScalar) {
            caret -= 1
        }
        guard caret >= targetLength else { return nil }

        let candidate = NSRange(location: caret - targetLength, length: targetLength)
        guard window.substring(with: candidate) == target else { return nil }

        // Extend over the trailing space that was stepped past, so the
        // replacement consumes it instead of leaving a doubled separator.
        return NSRange(
            location: windowStart + candidate.location,
            length: targetLength + (window.length - caret)
        )
    }
}
