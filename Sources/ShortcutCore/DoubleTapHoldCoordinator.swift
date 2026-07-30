import Foundation

/// What the caller should do with a hold event when double-tap-to-hands-free
/// is enabled.
enum DoubleTapDecision: Equatable {
    /// Hand the event to the session controller unchanged.
    case passThrough
    /// Ignore the event entirely.
    case swallow
    /// Hold the stop back for this long, in case a second tap is coming. If no
    /// second tap arrives the caller must re-deliver `.holdDeactivated`.
    case deferStop(after: TimeInterval)
    /// Second tap landed: keep the running recording but move it to hands-free.
    case latchToHandsFree
    /// Finish the hands-free session started by a double tap.
    case stopHandsFree
}

/// Adds "double-tap the hold key to go hands-free" without slowing normal
/// push-to-talk down.
///
/// The trick is that nothing is delayed on the way *in*. `Fn` down still starts
/// recording immediately; only the *stop* of an implausibly short hold is held
/// back long enough to see whether a second tap follows.
///
/// Two separate durations, which is the whole point:
///
/// - `maxTapDuration` decides whether a completed hold was a *tap* at all. Keep
///   it short: it bounds the worst-case added latency, and a hold this brief
///   cannot contain a spoken word, so real dictation never waits.
/// - `gap` is how long to wait after that tap's release for the second press.
///   Keep it generous: this is human reaction time, and being stingy here is
///   what makes a double-tap gesture feel broken.
///
/// Measuring both from the *press* of the first tap (one combined window) is the
/// bug this shape exists to avoid — it silently shrinks the user's reaction time
/// by however long they happened to hold the first tap.
///
/// Deliberately pure and clock-free: `now` is supplied by the caller so the
/// whole state machine is unit-testable without sleeping.
struct DoubleTapHoldCoordinator {
    /// A completed hold shorter than this counts as a tap. Bounds the worst-case
    /// added latency for a short push-to-talk.
    var maxTapDuration: TimeInterval
    /// Release-to-next-press window for the second tap.
    var gap: TimeInterval

    private var holdDownAt: TimeInterval?
    private var awaitingSecondTapUntil: TimeInterval?
    private(set) var handsFreeActive = false

    init(maxTapDuration: TimeInterval = 0.25, gap: TimeInterval = 0.40) {
        self.maxTapDuration = maxTapDuration
        self.gap = gap
    }

    /// True while a stop is being held back waiting for a possible second tap.
    var isDeferringStop: Bool { awaitingSecondTapUntil != nil }

    mutating func reset() {
        holdDownAt = nil
        awaitingSecondTapUntil = nil
        handsFreeActive = false
    }

    mutating func holdActivated(now: TimeInterval) -> DoubleTapDecision {
        // A tap while already hands-free is the stop gesture.
        if handsFreeActive {
            reset()
            return .stopHandsFree
        }

        // Second tap of a double tap: the first tap's recording is still
        // running because its stop was deferred, so keep the audio and just
        // change mode. Nothing is discarded and nothing restarts.
        if let deadline = awaitingSecondTapUntil, now <= deadline {
            awaitingSecondTapUntil = nil
            holdDownAt = nil
            handsFreeActive = true
            return .latchToHandsFree
        }

        // Stale deferral (the caller should already have re-delivered the stop).
        awaitingSecondTapUntil = nil
        holdDownAt = now
        return .passThrough
    }

    mutating func holdDeactivated(now: TimeInterval) -> DoubleTapDecision {
        if handsFreeActive {
            // The key-up half of a gesture we already acted on.
            return .swallow
        }

        // Gate on having seen the matching key-down, NOT on whether recording
        // actually started — a start can be deferred or refused, and neither
        // should disable the gesture.
        guard let downAt = holdDownAt else {
            return .passThrough
        }

        let heldFor = now - downAt
        holdDownAt = nil

        // Long enough to be speech: stop immediately, zero added latency.
        guard heldFor < maxTapDuration else {
            return .passThrough
        }

        // Implausibly short. Hold the stop back for the full reaction-time gap,
        // measured from this release rather than from the press.
        awaitingSecondTapUntil = now + gap
        return .deferStop(after: gap)
    }

    /// Called when a deferred stop's timer fires without a second tap.
    /// Returns false when a second tap already consumed it.
    mutating func deferredStopShouldProceed(now: TimeInterval) -> Bool {
        guard awaitingSecondTapUntil != nil else { return false }
        awaitingSecondTapUntil = nil
        return true
    }
}
