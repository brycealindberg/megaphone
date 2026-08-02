import Foundation

enum SmartCleanupValidationTests {
    static func run() {
        testSpokenProfanitySurvives()
        testTruncatedTranscriptIsRejected()
        testOrdinaryCleanupIsAccepted()
        testListFormattingIsAllowed()
        testRepeatedLineIsRejected()
        testBlockMarkdownIsRejected()
        testSelectionTransformsAreUnaffected()
        testAnsweredInsteadOfCleanedIsRejected()
        testTheSpeakersOwnOpeningIsNotAPreamble()
        testEchoedPromptIsRejected()
    }

    /// The model sometimes returns the hint block it was given instead of the
    /// transcript. Measured over 693 replayed dictations: 3 leaked the prompt and
    /// 2 were accepted — ~1,000 characters of Megaphone's own instructions, about
    /// to be pasted into a Slack channel. They clear the expansion ceiling by a
    /// hair, which is why length alone cannot catch this.
    private static func testEchoedPromptIsRejected() {
        let leak = """
        **Destination app:** Slack
        **Writing context:** Work chat
        **App-aware cleanup:** Use concise, professional chat formatting. Preserve the \
        speaker's tone and do not make the message more formal unless asked.
        """
        expectRejected(leak, source: "In the video generation from the keyframes in our app some of the movement during the videos of either people or backgrounds is choppy and I want to fix it")
        // The labels are shared with the prompt builder, so each one is checked.
        for label in AppleFoundationModelsPostProcessor.promptSectionLabels {
            expectRejected("\(label) Slack", source: "ship the build tonight")
        }
        // Someone genuinely dictating the phrase keeps it.
        expectAccepted("The writing context: work chat, like we discussed.",
                       source: "the writing context work chat like we discussed")
    }

    /// The assistant-preamble list was rejecting people for talking normally.
    /// Measured over 9,401 real dictations: 49 open with one of these phrases
    /// and every one was being downgraded to basic cleanup — which does not
    /// punctuate or capitalise — for no reason.
    private static func testTheSpeakersOwnOpeningIsNotAPreamble() {
        for (output, source) in [
            ("Here's the file on the concept and the scope of this project.",
             "Here's the file on the concept and the scope of this project"),
            ("I can't click View report. Please fix it using superpowers.",
             "I can't click view report. Please fix it using super powers"),
            ("Sure, we raise prices by 30%.", "Sure we raise prices by 30 percent."),
            ("Here is the context you need.", "Here is the context you need."),
            ("I'm sorry, I missed that.", "I'm sorry I missed that"),
        ] {
            expectAccepted(output, source: source)
        }
        // And the guard still catches a real preamble in front of text the
        // speaker did not open that way.
        expectRejected("Here's the cleaned transcript: ship the build tonight.",
                       source: "ship the build tonight")
        expectRejected("Certainly! I can help with that.", source: "what time is the standup")
        expectRejected("I'm sorry, I can't help with that.", source: "add milk to the list")
    }

    /// The model sometimes reads a rambling message as a request to WRITE one
    /// and returns an email instead of a tidied transcript. Both cases below are
    /// real outputs from replaying 140 dictations through the Slack profile, and
    /// both are shorter than their source — so the expansion ceiling and the
    /// dropped-most-of-it floor each let them through.
    private static func testAnsweredInsteadOfCleanedIsRejected() {
        expectRejected(
            "Hey team,\n\nI've got the checklist ready. Let's use it to stay on track and avoid unnecessary back-and-forth.\n\nBest,\n[Your Name]",
            source: "Yeah bro it's the same as before in what you would get once it's done. Yeah, just getting the checklist so we know and have a goal to complete instead of just going back and forth like we have been pretty much."
        )
        expectRejected(
            "Hey team,\n\nI've created a tool for ad generation for businesses. Would love to chat with anyone who wants to help close some deals.",
            source: "also guys I made this for ad generating for businesses would love to talk with some you if anyone wants to help close some deals on this already have it built out so just let me know"
        )
        // A greeting the speaker DID say survives being tidied, including when
        // the model changes its punctuation or the following words.
        expectAccepted("Hi Dana,\n\nThank you for the information. I just booked a call for Monday.",
                       source: "Hi Dana of course thank you too for the information I just booked a call for Monday")
        expectAccepted("Hey brother, my bad. I was feeling sick.",
                       source: "Hey brother my bad I was feeling sick")
        expectAccepted("Hey Sam, here's a little update video.",
                       source: "Hey Sam here's a little update video hope you're doing well")
        // An INLINE greeting is one spurious word on an otherwise good cleanup.
        // Rejecting it would cost the punctuation and capitalisation that basic
        // tidy does not do — the worse trade. Measured 4 of 693.
        expectAccepted("Hey, I'm free this weekend if you want to grab a coffee, I'd love that.",
                       source: "Yeah I'm free this weekend if you want to get a coffee I would love that.")
        expectAccepted("Hey Morgan, how's the week going for you?",
                       source: "yo morgan how's this week looking for you")
        // Ordinary text that merely mentions a bracket is not scaffolding.
        expectAccepted("Put the value in [brackets] like that.",
                       source: "put the value in brackets like that")
        // Selection transforms may legitimately produce either.
        expectAccepted("Hey team,\n\nHere is the update.\n\nBest,\n[Your Name]",
                       source: "write a short email to the team", allowsExpansion: true)
    }

    /// The on-device model sometimes truncates at, or paraphrases around, profanity even
    /// though the system prompt asks it to preserve it. Falling back to basic cleanup keeps
    /// the speaker's words instead of silently censoring them.
    private static func testSpokenProfanitySurvives() {
        expectRejected("What", source: "What the fuck?")
        expectRejected("I think we should ship this.", source: "What the fuck?")
        expectRejected("This is nonsense and I'm annoyed.", source: "This is bullshit and I'm pissed")

        expectAccepted("What the fuck?", source: "What the fuck?")
        expectAccepted("What the fuck, man.", source: "what the fuck man")
        expectAccepted("This is bullshit and I'm pissed.", source: "this is bullshit and I'm pissed")
    }

    private static func testTruncatedTranscriptIsRejected() {
        expectRejected(
            "Let's ship.",
            source: "Let's ship the release on Wednesday once the build finishes and QA signs off."
        )
    }

    private static func testOrdinaryCleanupIsAccepted() {
        expectAccepted("I think we should ship it.", source: "um so I think we should uh ship it you know")
        expectAccepted(
            "Let's meet Wednesday after lunch.",
            source: "let's meet Thursday no actually Wednesday after lunch"
        )
        expectAccepted("Is this working properly now?", source: "Is this working properly now?")
    }

    private static func testListFormattingIsAllowed() {
        expectAccepted("- option one\n- option two", source: "Give me the two options.")
        expectAccepted("1. First\n2. Second", source: "What are the steps?")
    }

    /// A short line answered with a restatement of itself. Measured on "deploy is
    /// green ✅", which came back as the sentence plus a bullet repeating it — too
    /// small an expansion for the length ceiling to catch.
    private static func testRepeatedLineIsRejected() {
        expectRejected("Deploy is green ✅\n\n- Deploy is green ✅", source: "deploy is green ✅")
        expectRejected("Ship the build.\nShip the build.", source: "ship the build")
        // The marker and the trailing full stop are not what makes it different.
        expectRejected("Wash the dishes\n- Wash the dishes.", source: "wash the dishes")

        // Genuinely different lines still pass, including a list whose items merely
        // start alike.
        expectAccepted("- Buy coffee\n- Buy tea", source: "buy coffee, buy tea")
        expectAccepted("Deploy is green ✅", source: "deploy is green ✅")
        expectAccepted("I want three things:\n- one\n- two", source: "I want three things, one, two")
    }

    /// Bullets are fine, but fencing or heading plain dictated prose never is.
    private static func testBlockMarkdownIsRejected() {
        expectRejected("```\nShip the build.\n```", source: "Ship the build.")
        expectRejected("# Ship the build.", source: "Ship the build.")
        expectRejected("> Ship the build.", source: "Ship the build.")

        expectAccepted(
            "```\nwrap the next line in a code block\n```",
            source: "wrap the next line in a code block"
        )
    }

    /// Selection rewrites legitimately shorten, expand, or reword text on request.
    private static func testSelectionTransformsAreUnaffected() {
        expectAccepted("Short.", source: "A much longer sentence that the user asked to shorten.", allowsExpansion: true)
        expectAccepted("Please review this.", source: "review this damn thing", allowsExpansion: true)
    }

    private static func expectRejected(
        _ output: String,
        source: String,
        allowsExpansion: Bool = false,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(
            !accepts(output, source: source, allowsExpansion: allowsExpansion),
            "Expected \(output.debugDescription) to be rejected for source \(source.debugDescription)",
            file: file,
            line: line
        )
    }

    private static func expectAccepted(
        _ output: String,
        source: String,
        allowsExpansion: Bool = false,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(
            accepts(output, source: source, allowsExpansion: allowsExpansion),
            "Expected \(output.debugDescription) to be accepted for source \(source.debugDescription)",
            file: file,
            line: line
        )
    }

    private static func accepts(_ output: String, source: String, allowsExpansion: Bool) -> Bool {
        do {
            try AppleFoundationModelsPostProcessor.validate(
                output,
                source: source,
                allowsExpansion: allowsExpansion
            )
            return true
        } catch {
            return false
        }
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
