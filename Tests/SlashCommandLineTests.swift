import Foundation

/// Reported 2026-08-05: dictating "/omp" shipped "/omp." and the command did
/// not fire. The period comes from the recogniser — it is already in the raw
/// transcript — so nothing upstream can be blamed or fixed instead.
enum SlashCommandLineTests {
    static func run() {
        testTheReportedCase()
        testOtherCommandShapes()
        testLeavesRealSentencesAlone()
        testNeverTouchesOtherTerminators()
        testIdempotentAndEmpty()
    }

    private static func testTheReportedCase() {
        expect(SlashCommandLine.stripTerminalPeriod("/omp."), "/omp")
    }

    private static func testOtherCommandShapes() {
        expect(SlashCommandLine.stripTerminalPeriod("/code-review."), "/code-review")
        expect(SlashCommandLine.stripTerminalPeriod("/ui_verify."), "/ui_verify")
        expect(SlashCommandLine.stripTerminalPeriod("/omp2."), "/omp2")
        // Already clean.
        expect(SlashCommandLine.stripTerminalPeriod("/omp"), "/omp")
    }

    /// The whole utterance must BE the command. A sentence that merely contains
    /// a path or a command keeps its punctuation — that is ordinary prose.
    private static func testLeavesRealSentencesAlone() {
        for s in ["check /etc/hosts.",
                  "/omp look at this.",
                  "run /omp then tell me.",
                  "the ratio is 3/4.",
                  "/.",
                  "/123.",
                  "hello."] {
            expect(SlashCommandLine.stripTerminalPeriod(s), s)
        }
    }

    /// Only a full stop. A "?" or "!" the speaker put there is theirs.
    private static func testNeverTouchesOtherTerminators() {
        expect(SlashCommandLine.stripTerminalPeriod("/omp?"), "/omp?")
        expect(SlashCommandLine.stripTerminalPeriod("/omp!"), "/omp!")
        // An ellipsis is not a sentence-closing stop either; only the last "."
        // would go, which would leave "/omp..", so the token check rejects it.
        expect(SlashCommandLine.stripTerminalPeriod("/omp..."), "/omp...")
    }

    private static func testIdempotentAndEmpty() {
        let once = SlashCommandLine.stripTerminalPeriod("/omp.")
        expect(SlashCommandLine.stripTerminalPeriod(once), once)
        expect(SlashCommandLine.stripTerminalPeriod(""), "")
        expect(SlashCommandLine.stripTerminalPeriod("."), ".")
    }

    private static func expect(_ got: String, _ want: String) {
        guard got == want else {
            fatalError("SlashCommandLine: wanted \"\(want)\", got \"\(got)\"")
        }
    }
}
