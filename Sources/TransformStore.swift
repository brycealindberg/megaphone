import Foundation

/// A named, reusable rewrite directive applied to the user's most recent
/// dictation by voice: "Hey Megaphone, polish that".
struct Transform: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var instruction: String
    var isBuiltIn: Bool = false

    /// Only user-defined transforms are persisted; built-ins live in code so
    /// their wording can improve between releases. Anything decoded from
    /// storage is therefore a user transform, never a built-in.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case instruction
    }
}

/// Built-in transforms plus deterministic voice-invocation matching.
///
/// Matching is intentionally not model-routed: a spoken wake command either
/// names a transform exactly (in one of a few fixed forms) and runs it, or it
/// falls through unchanged to the normal wake-command model.
enum TransformStore {
    static let polishInstruction = """
    Tighten the grammar and flow of the text. Remove filler words, stutters, and repeated phrasing. Keep the meaning, tone, hedges, and level of confidence exactly — "I think we should um maybe ship it" becomes "I think we should maybe ship it", keeping "I think" and "maybe". Keep roughly the original length and never add information or new sentences. When the text asks for something ("write me an announcement..."), keep it as that request — never produce the thing it asks for.
    """

    static let promptInstruction = """
    Rewrite the text as a prompt for an AI assistant, using exactly this layout: a "Goal:" line stating the action from the text as one short imperative sentence, then one "- " bullet for each condition or detail from the text that the Goal line does not already say. When nothing remains, output just the Goal line. Keep every requirement; invent nothing.
    Example: "so um write a poem about the sea i guess it should rhyme and keep it short" becomes:
    Goal: Write a poem about the sea.
    - It should rhyme.
    - Keep it short.
    Example: "i think we could try deploying the update tonight you know if the smoke tests look good" becomes:
    Goal: Deploy the update tonight.
    - Only if the smoke tests look good.
    """

    static let builtIns: [Transform] = [
        Transform(
            id: UUID(uuidString: "E1A7C7D2-4B1B-4F5A-9A64-6D0B4C8F1A01")!,
            name: "Polish",
            instruction: polishInstruction,
            isBuiltIn: true
        ),
        Transform(
            id: UUID(uuidString: "E1A7C7D2-4B1B-4F5A-9A64-6D0B4C8F1A02")!,
            name: "Prompt",
            instruction: promptInstruction,
            isBuiltIn: true
        )
    ]

    /// Built-ins merged with the user's transforms. A user transform whose
    /// name collides with a built-in (case- and punctuation-insensitively)
    /// shadows it, so "polish" can be re-purposed with custom wording.
    static func resolved(userTransforms: [Transform]) -> [Transform] {
        let userNames = Set(userTransforms.map { normalize($0.name) })
        let visibleBuiltIns = builtIns.filter { !userNames.contains(normalize($0.name)) }
        return visibleBuiltIns + userTransforms
    }

    /// Matches a wake command (wake phrase already stripped) against a
    /// transform invocation. Recognized forms, case- and
    /// punctuation-insensitive: "<name>", "<name> that", "<name> this", and
    /// "apply <name>". Names match whole — "polish that thing up" is not an
    /// invocation and falls through to the normal wake-command path.
    static func match(command: String, in transforms: [Transform]) -> Transform? {
        let normalizedCommand = normalize(command)
        guard !normalizedCommand.isEmpty else { return nil }
        return transforms.first { transform in
            let name = normalize(transform.name)
            guard !name.isEmpty else { return false }
            return normalizedCommand == name
                || normalizedCommand == name + " that"
                || normalizedCommand == name + " this"
                || normalizedCommand == "apply " + name
        }
    }

    /// Lowercases, turns punctuation and symbols into word separators, and
    /// collapses whitespace so spoken forms ("Polish that.", "meeting-notes")
    /// match stored names ("polish", "Meeting Notes").
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

// MARK: - reading a preference without destroying it

/// What was actually stored under a preference key, keeping "nothing saved yet"
/// apart from "something is saved that this build cannot read".
///
/// Every loader in this app used to collapse those two into one empty result:
///
///     guard let data = defaults.data(forKey: key),
///           let decoded = try? JSONDecoder().decode(T.self, from: data) else { return [] }
///
/// `data(forKey:)` returns nil for a value of the wrong type, so a mistyped
/// pref read as "nothing saved yet" — and on 2026-08-07 the save that followed
/// wrote fresh state over 322 hand-authored dictionary entries. The bytes were
/// still on disk right up to that write. Nothing looked at them, so nobody
/// could tell the difference until the data was gone.
enum StoredPreference<Value> {
    /// The key is absent. Seeding a default and saving it is safe.
    case missing
    /// The key held a value this build could read.
    case value(Value)
    /// The key holds something else. `PreferenceLoad` has already copied the
    /// raw value aside, so the app may carry on with a default.
    case unreadable

    /// The decoded value, or nil for both of the other cases. Call sites that
    /// only need "use this or a default" read this; call sites that must
    /// branch on *why* it is missing switch over the case instead.
    var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

/// Preference reads that cannot silently destroy what they failed to read.
///
/// This lives beside `Transform` rather than in a file of its own because the
/// build has no SwiftPM target: `Makefile` names every test-target source
/// twice, so a new file costs two registrations and a merge conflict for
/// anyone else editing that list. `user_transforms` is one of the payloads it
/// guards, so this is the least surprising home available. The other callers
/// are in `AppState.init`.
enum PreferenceLoad {
    /// Where an unreadable value is parked. A suffix rather than a prefix so
    /// the backup sorts next to the original in `defaults read` output, which
    /// is how a person recovers it.
    static func quarantineKey(for key: String) -> String { key + "__unreadable_backup" }

    /// Reads a JSON-encoded value, **and copies the stored value aside first
    /// if it cannot be read.** The copy is the whole point: the app still has
    /// to come up with something, and whatever it comes up with gets saved
    /// over the original sooner or later — on the next edit for the macro and
    /// transform lists, immediately at launch for the dictation profiles.
    static func json<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String,
        from defaults: UserDefaults = .standard
    ) -> StoredPreference<Value> {
        guard defaults.object(forKey: key) != nil else { return .missing }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Value.self, from: data) else {
            quarantine(forKey: key, in: defaults)
            return .unreadable
        }
        return .value(decoded)
    }

    /// The same guard for the hand-authored text prefs. `string(forKey:)`
    /// returns nil for an array, dictionary or data value, so those empty a
    /// `TextEditor` that then writes the empty string back on the first
    /// keystroke.
    static func string(
        forKey key: String,
        from defaults: UserDefaults = .standard
    ) -> StoredPreference<String> {
        guard defaults.object(forKey: key) != nil else { return .missing }
        guard let stored = defaults.string(forKey: key) else {
            quarantine(forKey: key, in: defaults)
            return .unreadable
        }
        return .value(stored)
    }

    /// Copies an unreadable value to its quarantine key, once.
    ///
    /// Nothing in the app reads the copy back. It exists so the data is still
    /// recoverable by hand rather than gone:
    ///
    ///     defaults read com.kuberwastaken.megaphone <key>__unreadable_backup
    ///
    /// An existing backup is never replaced. The first one holds the user's
    /// real work; a second corruption would otherwise overwrite it with
    /// whatever garbage arrived after the app had already started fresh.
    @discardableResult
    static func quarantine(forKey key: String, in defaults: UserDefaults) -> Bool {
        let backupKey = quarantineKey(for: key)
        guard defaults.object(forKey: backupKey) == nil,
              let stored = defaults.object(forKey: key) else { return false }
        defaults.set(stored, forKey: backupKey)
        return true
    }
}
