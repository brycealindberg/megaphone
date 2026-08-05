import Foundation

enum CaretPrecedingSelectionTests {
    static func run() {
        testMatchesImmediatelyBeforeCaret()
        testTrailingSpaceIsConsumed()
        testRejectsWhenTextDoesNotPrecedeCaret()
        testRejectsShortWindowAndEmptyTarget()
        testWindowOffsetsAreAbsolute()
        testWindowedAgreesWithWholeValue()
        testAstralPlaneUsesUTF16Lengths()
        testWindowRangeCoversWhatAMatchCanUse()
        testMalformedReadIsRejectedNotRemapped()
    }

    /// The base case: the target sits flush against the caret.
    private static func testMatchesImmediatelyBeforeCaret() {
        let range = selection(target: "hello there", value: "well hello there", caret: 16)
        expect(range?.location, 5, "match starts after the preceding word")
        expect(range?.length, 11, "match covers exactly the target")
    }

    /// The convenience space dictation appends has to be selected too, or the
    /// replacement leaves a doubled separator behind.
    private static func testTrailingSpaceIsConsumed() {
        let range = selection(target: "ship it.", value: "ok, ship it. ", caret: 13)
        expect(range?.location, 4, "selection starts at the target")
        expect(range?.length, 9, "selection covers the target plus the space")

        let newline = selection(target: "ship it.", value: "ok, ship it.\n", caret: 13)
        expect(newline?.length, 9, "a newline counts as the trailing whitespace")
    }

    /// The safety property this whole function exists for: if the user moved the
    /// caret or edited the text, select nothing.
    private static func testRejectsWhenTextDoesNotPrecedeCaret() {
        expect(selection(target: "hello", value: "hello there", caret: 11) == nil, true,
               "target is not adjacent to the caret")
        expect(selection(target: "hello", value: "hello there", caret: 8) == nil, true,
               "caret lands mid-word")
        expect(selection(target: "goodbye", value: "well hello", caret: 10) == nil, true,
               "target absent entirely")
        // Two spaces: only one is stepped over, so the target no longer abuts.
        expect(selection(target: "hi", value: "say hi  ", caret: 8) == nil, true,
               "only a single trailing whitespace is forgiven")
    }

    private static func testRejectsShortWindowAndEmptyTarget() {
        expect(selection(target: "hello there", value: "there", caret: 5) == nil, true,
               "window shorter than the target")
        expect(selection(target: "", value: "anything", caret: 8) == nil, true,
               "empty target never selects")
        expect(CaretPrecedingSelection.selectionRange(
            matching: "hi", endingAt: "say hi" as NSString, windowStart: -1) == nil, true,
               "negative window start is rejected")
    }

    /// A ranged read starts partway into the field, so the returned coordinates
    /// have to be shifted back into the element's own space.
    private static func testWindowOffsetsAreAbsolute() {
        // Field is "...<2000 chars>...please send it", read only the last 15.
        let range = CaretPrecedingSelection.selectionRange(
            matching: "send it", endingAt: "please send it" as NSString, windowStart: 2000)
        expect(range?.location, 2007, "location is offset by the window start")
        expect(range?.length, 7, "length is unaffected by the offset")
    }

    /// The change this guards: `selectTextImmediatelyBeforeCaret` now prefers a
    /// ranged read and falls back to the whole value. For every caret the two
    /// must produce the identical range — otherwise the fast path overwrites
    /// different text than the slow one.
    ///
    /// Drives `windowRange` + `evaluate`, the same calls production makes, so
    /// that changing how the window is framed breaks this test. Recomputing the
    /// framing here instead would let the two drift apart silently.
    private static func testWindowedAgreesWithWholeValue() {
        let value = "Morning. Can you send the invoice over today. " as NSString
        let targets = ["send the invoice over today.", "today.", "Morning.", "nope", ""]
        for target in targets {
            for caret in 0...value.length {
                let whole = wholeValueOutcome(target: target, value: value, caret: caret)

                guard let requested = CaretPrecedingSelection.windowRange(
                    target: target, caret: caret
                ) else {
                    // No ranged read possible; production falls back, and the
                    // fallback must itself decline.
                    expect(whole, .noMatch, "no window at caret \(caret) for \(target)")
                    continue
                }
                expect(requested.location + requested.length, caret,
                       "window ends at the caret, caret \(caret) for \(target)")
                let windowed = CaretPrecedingSelection.evaluate(
                    target: target,
                    window: value.substring(with: requested) as NSString,
                    requested: requested
                )
                expect(windowed, whole, "ranged and whole agree at caret \(caret) for \(target)")
            }
        }
    }

    /// The window must cover every character a match could consume — the target
    /// plus the one convenience space — and never start before the field does.
    private static func testWindowRangeCoversWhatAMatchCanUse() {
        let range = CaretPrecedingSelection.windowRange(target: "today.", caret: 100)
        expect(range?.location, 93, "starts target+1 before the caret")
        expect(range?.length, 7, "covers the target plus one whitespace")

        let clamped = CaretPrecedingSelection.windowRange(target: "today.", caret: 6)
        expect(clamped?.location, 0, "never starts before the field")
        expect(clamped?.length, 6, "shortened to what exists")

        expect(CaretPrecedingSelection.windowRange(target: "today.", caret: 5) == nil, true,
               "caret closer than the target cannot match")
        expect(CaretPrecedingSelection.windowRange(target: "", caret: 10) == nil, true,
               "empty target has no window")
    }

    /// The finding this exists for. An element that clamps a range answers
    /// .success with a SHORT string. Credited to the requested start, a read of
    /// "hello" that really came from offsets 5-10 would select 4-9 and paste
    /// over a character the user never dictated. It must be refused outright.
    private static func testMalformedReadIsRejectedNotRemapped() {
        let requested = NSRange(location: 4, length: 6)   // asked for 6 units at 4

        expect(CaretPrecedingSelection.evaluate(
            target: "hello", window: "hello" as NSString, requested: requested),
            .invalidRead, "a one-short response is refused, not remapped")

        expect(CaretPrecedingSelection.evaluate(
            target: "hello", window: "hello!!" as NSString, requested: requested),
            .invalidRead, "an over-long response is refused too")

        expect(CaretPrecedingSelection.evaluate(
            target: "hello", window: "" as NSString, requested: requested),
            .invalidRead, "an empty response is refused")

        expect(CaretPrecedingSelection.evaluate(
            target: "hello", window: "hello" as NSString,
            requested: NSRange(location: -1, length: 5)),
            .invalidRead, "a negative start is refused")

        // The well-formed control: same target, a response that does answer the
        // request, and the selection lands where the request said it would.
        expect(CaretPrecedingSelection.evaluate(
            target: "hello", window: "y hello" as NSString,
            requested: NSRange(location: 4, length: 7)),
            .selection(NSRange(location: 6, length: 5)),
            "a well-formed response selects at the requested offset")

        expect(CaretPrecedingSelection.evaluate(
            target: "hello", window: "goodbye" as NSString, requested: NSRange(location: 4, length: 7)),
            .noMatch, "a valid window without the target is a definitive no")
    }

    /// Mirrors production's whole-value fallback, including its bounds check.
    private static func wholeValueOutcome(
        target: String, value: NSString, caret: Int
    ) -> CaretPrecedingSelection.Outcome {
        guard caret <= value.length else { return .invalidRead }
        return CaretPrecedingSelection.evaluate(
            target: target,
            window: value.substring(to: caret) as NSString,
            requested: NSRange(location: 0, length: caret)
        )
    }

    /// Accessibility ranges are UTF-16, and an emoji is two code units. Counting
    /// Characters here would select a range shorter than the target and paste
    /// over half a surrogate pair.
    private static func testAstralPlaneUsesUTF16Lengths() {
        // "ok ship it 🚀" is 13 UTF-16 units — the rocket occupies 11 and 12.
        let range = selection(target: "ship it 🚀", value: "ok ship it 🚀", caret: 13)
        expect(range?.location, 3, "starts after the two-unit prefix")
        expect(range?.length, 10, "length counts the emoji as two UTF-16 units")

        // A caret landing between the surrogates must not match: the window ends
        // mid-character, so the comparison fails and the document is left alone.
        expect(selection(target: "ship it 🚀", value: "ok ship it 🚀", caret: 12) == nil, true,
               "caret inside a surrogate pair selects nothing")
    }

    // MARK: helpers

    /// Mirrors the whole-value fallback: everything up to the caret is the window.
    private static func selection(target: String, value: String, caret: Int) -> NSRange? {
        let ns = value as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        return CaretPrecedingSelection.selectionRange(
            matching: target, endingAt: ns.substring(to: caret) as NSString, windowStart: 0)
    }

    private static func expect<T: Equatable>(_ got: T, _ want: T, _ what: String) {
        guard got == want else {
            fatalError("CaretPrecedingSelection: \(what) — wanted \(want), got \(got)")
        }
    }
}
