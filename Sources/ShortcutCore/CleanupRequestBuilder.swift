import Foundation

/// Everything the cleanup prompt is built from except the transcript.
///
/// Built twice per dictation: once while the user is still speaking, to prefill
/// the prompt head via `prewarm(promptPrefix:)`, and once at stop time for the
/// real request. The prefix is only worth anything if those two prompts are
/// byte-identical, so both go through here and neither derives a field on its
/// own.
///
/// Deliberately pure and parameter-only — it takes no `AppState` and reads no
/// shared state. It is called from the main queue during recording and from the
/// transcription task at stop, and anything it read for itself would be a way
/// for the two to disagree.
///
/// Measured payoff for the prefill, 60 real cases, freshly prepared session each
/// time: 850 ms with a bare `prewarm()` against 668 ms with the prefix, and
/// byte-identical model output on all 60.
struct CleanupPlan {
    let context: AppContext
    let vocabulary: [String]
    let corrections: [TranscriptTidier.CorrectionMapping]
    let writingContext: AppWritingContext
    let profile: DictationProfile
    let formality: WritingFormality
    let outputLanguage: String
    let customInstructions: String

    static func make(
        context: AppContext,
        customVocabulary: String,
        screenText: String,
        wordCorrections: String,
        customSystemPrompt: String,
        customContextPrompt: String,
        outputLanguage: String,
        profiles: DictationProfileSet
    ) -> CleanupPlan {
        let vocabulary = ScreenVocabulary.rankingForScreen(
            customVocabulary
                .split { $0 == "," || $0.isNewline }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            screenText: screenText
        )
        // The writing context for wherever this dictation lands, resolved from
        // the context captured at recording time. Drives both the formality
        // dial and casual-chat punctuation lightening.
        let writingContext = AppWritingContext.classify(
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle
        )
        // One profile decides everything that varies by destination app.
        let profile = profiles.profile(for: writingContext)
        return CleanupPlan(
            context: context,
            vocabulary: vocabulary,
            corrections: TranscriptTidier.CorrectionMapping.parse(wordCorrections),
            writingContext: writingContext,
            profile: profile,
            // Code and terminal apps stay exempt from the register dial.
            formality: writingContext == .codeOrTerminal ? .balanced : profile.formality,
            outputLanguage: outputLanguage,
            customInstructions: [customSystemPrompt, customContextPrompt]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        )
    }

    /// The only place a `SmartCleanupRequest` is built.
    ///
    /// `transcript` is the one field that cannot be known during recording, and
    /// it is also the only field the prompt *prefix* ignores — so the prewarm
    /// path calls this with `""` and still gets the prefix the real request will
    /// produce.
    func request(transcript: String) -> SmartCleanupRequest {
        SmartCleanupRequest(
            transcript: transcript,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            selectedText: context.selectedText,
            textBeforeCaret: context.textBeforeCaret,
            contextSummary: context.contextSummary,
            vocabulary: vocabulary,
            corrections: corrections.map {
                SmartCleanupRequest.Correction(heard: $0.spoken, written: $0.replacement)
            },
            outputLanguage: outputLanguage,
            customInstructions: customInstructions,
            formality: formality,
            allowStructure: profile.lists
        )
    }
}
