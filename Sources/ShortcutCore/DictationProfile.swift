import Foundation

/// Everything that varies by where a dictation lands, bundled per writing
/// context. Megaphone already detects the destination app and sorts it into one
/// of six `AppWritingContext` cases; a profile is what each of those six then
/// applies.
///
/// A profile controls **formatting and register only**. It is deliberately not a
/// voice or style instruction: the words stay the speaker's, and every switch
/// here maps to a deterministic post-step or to the existing formality dial, not
/// to freeform prose in the cleanup prompt. Small on-device models follow those
/// instructions unreliably, so anything added here should be a switch over
/// measured code — not a sentence.
struct DictationProfile: Codable, Equatable, Sendable {
    /// Register dial handed to Smart Cleanup. Never a rewrite instruction.
    var formality: WritingFormality
    /// Strip the commas a cleanup model sprinkles into short chat lines.
    var lightCommas: Bool
    /// Add a "?" to wording that is plainly a question.
    var questionMarks: Bool
    /// Let a dictated enumeration become real lines.
    var lists: Bool
    /// Drop the abandoned clause of a spoken restart.
    var restarts: Bool
    /// Lower-case a dictation that continues an unfinished sentence.
    var lowercaseContinuations: Bool
    /// Learn vocabulary from edits made by hand after a dictation.
    var learnEdits: Bool

    init(
        formality: WritingFormality = .balanced,
        lightCommas: Bool = false,
        questionMarks: Bool = true,
        lists: Bool = true,
        restarts: Bool = true,
        lowercaseContinuations: Bool = true,
        learnEdits: Bool = true
    ) {
        self.formality = formality
        self.lightCommas = lightCommas
        self.questionMarks = questionMarks
        self.lists = lists
        self.restarts = restarts
        self.lowercaseContinuations = lowercaseContinuations
        self.learnEdits = learnEdits
    }

    /// Decoding tolerates a profile written by an older build that lacked a
    /// switch, so adding one never wipes a saved profile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DictationProfile()
        formality = try c.decodeIfPresent(WritingFormality.self, forKey: .formality) ?? fallback.formality
        lightCommas = try c.decodeIfPresent(Bool.self, forKey: .lightCommas) ?? fallback.lightCommas
        questionMarks = try c.decodeIfPresent(Bool.self, forKey: .questionMarks) ?? fallback.questionMarks
        lists = try c.decodeIfPresent(Bool.self, forKey: .lists) ?? fallback.lists
        restarts = try c.decodeIfPresent(Bool.self, forKey: .restarts) ?? fallback.restarts
        lowercaseContinuations = try c.decodeIfPresent(Bool.self, forKey: .lowercaseContinuations)
            ?? fallback.lowercaseContinuations
        learnEdits = try c.decodeIfPresent(Bool.self, forKey: .learnEdits) ?? fallback.learnEdits
    }

    /// The shipped profile for a context, used for a fresh install and as the
    /// fallback for any context missing from the saved set.
    static func standard(for context: AppWritingContext) -> DictationProfile {
        switch context {
        case .casualChat:
            // Chat is the one place light commas belong, and the register is
            // relaxed. Lists are on here too, which stock Megaphone forbids.
            return DictationProfile(formality: .casual, lightCommas: true)
        case .email:
            return DictationProfile(formality: .formal)
        case .workChat, .document, .codeOrTerminal, .neutral:
            return DictationProfile(formality: .balanced)
        }
    }
}

/// The six profiles, keyed by `AppWritingContext.rawValue` so the stored JSON
/// stays readable and survives reordering the enum.
struct DictationProfileSet: Codable, Equatable, Sendable {
    var byContext: [String: DictationProfile]

    init(byContext: [String: DictationProfile] = [:]) {
        self.byContext = byContext
    }

    static var standard: DictationProfileSet {
        var set = DictationProfileSet()
        for context in AppWritingContext.allContexts {
            set.byContext[context.rawValue] = .standard(for: context)
        }
        return set
    }

    func profile(for context: AppWritingContext) -> DictationProfile {
        byContext[context.rawValue] ?? .standard(for: context)
    }

    mutating func set(_ profile: DictationProfile, for context: AppWritingContext) {
        byContext[context.rawValue] = profile
    }

    // MARK: - migration

    /// The global switches this replaces, read once so a user who had them set
    /// keeps exactly the behaviour they already had.
    struct LegacySwitches {
        var lightCommasInCasualChat: Bool
        var questionMarks: Bool
        var questionMarksInCode: Bool
        var listsInCode: Bool
        var listsInCasualChat: Bool
        var restarts: Bool
        var lowercaseContinuations: Bool
        var learnEdits: Bool
    }

    /// Builds the six profiles from the old global switches plus the old
    /// per-context formality dictionary. Behaviour-preserving by construction:
    /// each context gets what the globals would have produced *in that context*,
    /// including the two flags that were already context-specific.
    static func migrating(
        legacy: LegacySwitches,
        formalityByContext: [String: String]
    ) -> DictationProfileSet {
        var set = DictationProfileSet()
        for context in AppWritingContext.allContexts {
            let formality = WritingFormality(rawValue: formalityByContext[context.rawValue] ?? "")
                ?? DictationProfile.standard(for: context).formality
            let lists: Bool
            switch context {
            case .codeOrTerminal: lists = legacy.listsInCode
            case .casualChat: lists = legacy.listsInCasualChat
            default: lists = true
            }
            set.byContext[context.rawValue] = DictationProfile(
                formality: formality,
                lightCommas: context == .casualChat ? legacy.lightCommasInCasualChat : false,
                // The old question-mark flag had a code/terminal sub-switch, so
                // that context needs both to have been on.
                questionMarks: context == .codeOrTerminal
                    ? (legacy.questionMarks && legacy.questionMarksInCode)
                    : legacy.questionMarks,
                lists: lists,
                restarts: legacy.restarts,
                lowercaseContinuations: legacy.lowercaseContinuations,
                learnEdits: legacy.learnEdits
            )
        }
        return set
    }
}

extension AppWritingContext {
    /// Every context, in the order the settings UI lists them.
    static let allContexts: [AppWritingContext] = [
        .casualChat, .workChat, .email, .document, .codeOrTerminal, .neutral
    ]

    /// Which apps land here, shown beside the profile so the mapping is visible.
    var exampleApps: String {
        switch self {
        case .casualChat: return "WhatsApp, Messages, Discord, Telegram"
        case .workChat: return "Slack, Teams"
        case .email: return "Mail, Gmail, Outlook"
        case .document: return "Notes, Obsidian, Notion, Pages, Docs"
        case .codeOrTerminal: return "Ghostty, iTerm, VS Code, Cursor, Xcode, Zed"
        case .neutral: return "everything else, including browser text fields"
        }
    }

    /// Title case for a settings row.
    var profileTitle: String {
        switch self {
        case .casualChat: return "Personal Chat"
        case .workChat: return "Work Chat"
        case .email: return "Email"
        case .document: return "Documents"
        case .codeOrTerminal: return "Code & Terminal"
        case .neutral: return "Everything Else"
        }
    }
}
