import Foundation

enum DoubleTapHoldCoordinatorTests {
    static func run() {
        testRealDictationIsNeverDelayed()
        testDoubleTapLatchesToHandsFree()
        testReactionTimeDoesNotShrinkWithFirstTapLength()
        testSingleShortTapStillDictates()
        testTapWhileHandsFreeStops()
        testSecondTapAfterGapIsANewHold()
        testKeyUpAfterLatchIsSwallowed()
        testDeactivateWithoutMatchingDownPassesThrough()
        testLatchDoesNotRequireRecordingToHaveStarted()
    }

    /// The whole point: a hold long enough to contain speech must stop the
    /// instant the key comes up, with no deferral.
    private static func testRealDictationIsNeverDelayed() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        expect(c.holdActivated(now: 0), .passThrough, "hold down starts immediately")
        expect(c.holdDeactivated(now: 1.8), .passThrough, "1.8s hold stops immediately")
        expect(c.isDeferringStop, false, "no stop deferral for real speech")

        // Right at the boundary: 0.25s is not a tap, so it must not be delayed.
        var b = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        _ = b.holdActivated(now: 0)
        expect(b.holdDeactivated(now: 0.25), .passThrough, "maxTapDuration is exclusive")
    }

    private static func testDoubleTapLatchesToHandsFree() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        _ = c.holdActivated(now: 0)
        expect(c.holdDeactivated(now: 0.05), .deferStop(after: 0.40), "tap defers by the full gap")
        expect(c.holdActivated(now: 0.30), .latchToHandsFree, "second tap inside the gap latches")
        expect(c.handsFreeActive, true, "hands-free is now active")
        expect(c.isDeferringStop, false, "deferral consumed")
    }

    /// The regression this shape exists for. Measuring the window from the first
    /// tap's *press* left only `window - heldFor` to land the second tap, so a
    /// deliberate 200ms first tap gave the user 50ms — unhittable in practice.
    /// The gap must be independent of how long tap one was held.
    private static func testReactionTimeDoesNotShrinkWithFirstTapLength() {
        for firstTapLength in [0.01, 0.10, 0.20, 0.24] {
            var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
            _ = c.holdActivated(now: 0)
            expect(
                c.holdDeactivated(now: firstTapLength),
                .deferStop(after: 0.40),
                "a \(firstTapLength)s first tap still yields the full 0.40s gap"
            )
            // Second tap 0.35s after release: comfortably human, must latch
            // regardless of how long the first tap was held.
            expect(
                c.holdActivated(now: firstTapLength + 0.35),
                .latchToHandsFree,
                "latches after a \(firstTapLength)s first tap"
            )
        }
    }

    /// One quick tap and nothing else must still produce a normal dictation.
    private static func testSingleShortTapStillDictates() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        _ = c.holdActivated(now: 0)
        expect(c.holdDeactivated(now: 0.05), .deferStop(after: 0.40), "defers")
        expect(c.deferredStopShouldProceed(now: 0.45), true, "timer fires -> real stop happens")
        expect(c.handsFreeActive, false, "did not become hands-free")
    }

    private static func testTapWhileHandsFreeStops() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        _ = c.holdActivated(now: 0)
        _ = c.holdDeactivated(now: 0.05)
        _ = c.holdActivated(now: 0.30)
        expect(c.handsFreeActive, true, "hands-free active")
        expect(c.holdActivated(now: 9.0), .stopHandsFree, "later tap ends hands-free")
        expect(c.handsFreeActive, false, "reset after stop")
    }

    private static func testSecondTapAfterGapIsANewHold() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        _ = c.holdActivated(now: 0)
        _ = c.holdDeactivated(now: 0.05)
        // Deferred stop already fired at 0.45; a tap at 1.2 is unrelated.
        _ = c.deferredStopShouldProceed(now: 0.45)
        expect(c.holdActivated(now: 1.2), .passThrough, "late tap is a fresh hold")
        expect(c.handsFreeActive, false, "not hands-free")
    }

    private static func testKeyUpAfterLatchIsSwallowed() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        _ = c.holdActivated(now: 0)
        _ = c.holdDeactivated(now: 0.05)
        _ = c.holdActivated(now: 0.30)
        expect(c.holdDeactivated(now: 0.36), .swallow,
               "releasing the second tap must not stop the hands-free session")
        expect(c.handsFreeActive, true, "still hands-free")
    }

    /// A key-up with no matching key-down (monitor started mid-press, tap reset)
    /// must not be swallowed or deferred.
    private static func testDeactivateWithoutMatchingDownPassesThrough() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        expect(c.holdDeactivated(now: 5.0), .passThrough, "orphan key-up passes through")
        expect(c.isDeferringStop, false, "nothing deferred")
    }

    /// The gesture must not depend on recording having actually started — the
    /// start can be delayed by `shortcutStartDelay` or refused outright.
    private static func testLatchDoesNotRequireRecordingToHaveStarted() {
        var c = DoubleTapHoldCoordinator(maxTapDuration: 0.25, gap: 0.40)
        _ = c.holdActivated(now: 0)
        expect(c.holdDeactivated(now: 0.04), .deferStop(after: 0.40), "defers with no recording")
        expect(c.holdActivated(now: 0.20), .latchToHandsFree, "still latches")
    }

    // MARK: helpers

    private static func expect(
        _ got: DoubleTapDecision,
        _ want: DoubleTapDecision,
        _ what: String
    ) {
        if case .deferStop(let g) = got, case .deferStop(let w) = want {
            guard abs(g - w) < 0.0001 else {
                fatalError("DoubleTapHoldCoordinator: \(what) — wanted deferStop(\(w)), got deferStop(\(g))")
            }
            return
        }
        guard got == want else {
            fatalError("DoubleTapHoldCoordinator: \(what) — wanted \(want), got \(got)")
        }
    }

    private static func expect(_ got: Bool, _ want: Bool, _ what: String) {
        guard got == want else {
            fatalError("DoubleTapHoldCoordinator: \(what) — wanted \(want), got \(got)")
        }
    }
}
