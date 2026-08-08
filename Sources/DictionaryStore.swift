import Foundation
import Combine

struct DictionaryEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable, CaseIterable {
        case manual
        case learned
    }

    enum Status: String, Codable, CaseIterable {
        case suggested
        case active
        case rejected
    }

    var id: UUID
    var term: String
    var source: Source
    var status: Status
    var isEnabled: Bool
    var observationCount: Int
    var starred: Bool
    var usageCount: Int
    var createdAt: Date
    var updatedAt: Date
    /// What the recogniser actually wrote, when this entry was learned from an
    /// edit. Kept because it is the half that makes a correction *actionable*:
    /// a term alone can only be offered to the model as a preferred spelling
    /// (advisory, and capped at 40), whereas a heard->written pair can become a
    /// deterministic `word_corrections` rule that always fires. It was being
    /// discarded at the moment of learning, so 161 learned entries have no way
    /// back to what they were meant to fix.
    var observedSource: String?
    /// How many times a hand-edit confirmed this term was MISHEARD.
    ///
    /// Deliberately not `observationCount`, which is written by two callers
    /// with opposite meanings: `observe(candidateTerms:)` bumps it on every
    /// successful dictation in which the term merely appears. Measured
    /// 2026-08-02 against the real store — one mishearing followed by two
    /// correct dictations leaves `observationCount == 3`, so a gate reading it
    /// is satisfied by evidence the correction is NOT needed. This field is
    /// touched only on the edit path, and only when the edit is more than a
    /// change of case.
    var misheardCount: Int

    init(
        id: UUID = UUID(),
        term: String,
        source: Source,
        status: Status,
        isEnabled: Bool = true,
        observationCount: Int = 0,
        starred: Bool = false,
        usageCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        observedSource: String? = nil,
        misheardCount: Int = 0
    ) {
        self.id = id
        self.term = term
        self.source = source
        self.status = status
        self.isEnabled = isEnabled
        self.observationCount = observationCount
        self.starred = starred
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.observedSource = observedSource
        self.misheardCount = misheardCount
    }

    /// Entries stored before starring/usage ranking shipped lack these keys;
    /// decode them with safe defaults so existing dictionaries keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        source = try container.decode(Source.self, forKey: .source)
        status = try container.decode(Status.self, forKey: .status)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        observationCount = try container.decode(Int.self, forKey: .observationCount)
        starred = try container.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        observedSource = try container.decodeIfPresent(String.self, forKey: .observedSource)
        misheardCount = try container.decodeIfPresent(Int.self, forKey: .misheardCount) ?? 0
    }

    /// Prompt-facing ranking: starred terms first, then most-used, then
    /// alphabetical — so downstream caps (e.g. `prefix(40)`) keep the terms
    /// the user actually relies on.
    static func promptRanking(_ lhs: DictionaryEntry, _ rhs: DictionaryEntry) -> Bool {
        if lhs.starred != rhs.starred { return lhs.starred }
        if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
        return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
    }
}

enum DictionaryStoreError: LocalizedError, Equatable {
    case emptyTerm
    case duplicateTerm

    var errorDescription: String? {
        switch self {
        case .emptyTerm: return "Enter a word or phrase."
        case .duplicateTerm: return "That word or phrase is already in your Dictionary."
        }
    }
}

/// What was found in the stored Dictionary when it could not be read back, and
/// where the original value was parked for safekeeping.
///
/// The distinction that matters is UNREADABLE vs ABSENT. On 2026-08-07 the
/// `dictionary_entries_v1` value came back as a *string* where Data belongs;
/// `data(forKey:)` answers nil for that exactly as it does for a key that was
/// never written, so `load` returned `[]` and the store came up looking like a
/// first run — empty AND writable. Four terms learned over the next two minutes
/// were then persisted over 322, and only an unrelated backup taken minutes
/// earlier got them back. Nothing in the app said a word about it.
struct DictionaryStorageIncident: Equatable {
    enum Reason: Equatable {
        /// Something is stored under the key, but not as Data. The shape of the
        /// real incident.
        case wrongType(described: String)
        /// Data, but not a `[DictionaryEntry]` JSON array — truncated, half
        /// written, or written by something that is not this app.
        case undecodable(byteCount: Int)
    }

    var reason: Reason
    /// `false` when the value was only stored under the wrong *type* and its
    /// bytes still decoded into entries. Nothing was lost in that case, so
    /// saving carries on and the next write puts the value back to Data.
    var blocksSaving: Bool
    /// Sibling defaults key holding the original value verbatim, in whatever
    /// type it arrived as. Same domain as the dictionary itself, so `defaults
    /// read` reaches it without knowing anything about this code.
    var quarantineKey: String
    /// A byte-for-byte copy written outside the preferences plist, when one
    /// could be written. Preferences are the thing under suspicion here, so the
    /// copy that matters should not live in them.
    var quarantineFileURL: URL?

    /// One line for the menu bar. States what has been lost (nothing yet) and
    /// where to go, because silence is what made 2026-08-07 catastrophic.
    var summary: String {
        blocksSaving
            ? "Your Dictionary can't be read, so Megaphone stopped saving to it. Nothing has been overwritten. Open Settings > Dictionary."
            : "Your Dictionary was stored in the wrong format and has been repaired. No words were lost."
    }

    /// The Settings version: names the fault and the recovery copy, so someone
    /// can get their words back by hand without a support conversation.
    var detail: String {
        var lines: [String] = []
        switch reason {
        case .wrongType(let described):
            lines.append("Megaphone expected the saved Dictionary to be stored as data and found \(described) instead.")
        case .undecodable(let byteCount):
            lines.append("The saved Dictionary is \(byteCount) bytes of data that Megaphone can no longer read.")
        }
        if blocksSaving {
            lines.append("Saving is paused, so this session's learning is being dropped rather than written over your saved words.")
        }
        lines.append("The original value was kept in the preference \(quarantineKey).")
        if let quarantineFileURL {
            lines.append("A copy is also at \(quarantineFileURL.path).")
        }
        return lines.joined(separator: " ")
    }
}

/// Portable snapshot of the private Dictionary written by Export and read by
/// Import in Settings, so a second Mac can be taught from a file instead of
/// from scratch — no account or server involved. Dates are ISO-8601 so the
/// file stays human-readable and editable.
struct DictionaryExportDocument: Codable {
    static let currentVersion = 1

    var megaphoneDictionaryVersion: Int
    var exportedAt: Date
    var entries: [DictionaryEntry]
    var exactCorrections: String

    init(entries: [DictionaryEntry], exactCorrections: String, exportedAt: Date = Date()) {
        self.megaphoneDictionaryVersion = Self.currentVersion
        self.exportedAt = exportedAt
        self.entries = entries
        self.exactCorrections = exactCorrections
    }

    /// Only the version key and entries are required, so a hand-trimmed file
    /// (for example one with corrections removed) still imports.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        megaphoneDictionaryVersion = try container.decode(Int.self, forKey: .megaphoneDictionaryVersion)
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        entries = try container.decodeIfPresent([DictionaryEntry].self, forKey: .entries) ?? []
        exactCorrections = try container.decodeIfPresent(String.self, forKey: .exactCorrections) ?? ""
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> DictionaryExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DictionaryExportDocument.self, from: data)
    }
}

struct DictionaryImportResult: Equatable {
    var addedCount = 0
    var updatedCount = 0
}

/// Local, privacy-preserving vocabulary used by speech recognition and cleanup.
/// Learned entries remain suggestions until independently observed several times.
final class DictionaryStore: ObservableObject {
    static let learningThreshold = 3
    /// Sightings needed when the evidence is the user *correcting* a word by
    /// hand, rather than merely saying it. Lower than `learningThreshold`
    /// because an edit is deliberate, but above 1 so a single misread edit
    /// cannot start biasing recognition on its own.
    static let editLearningThreshold = 2
    static let learnedEntryLimit = 300
    static let suggestionLimit = 100
    static let shared = DictionaryStore()

    /// Suffixes for the two sibling keys the quarantine uses. Derived from the
    /// storage key rather than hard-coded so a store pointed at a test suite
    /// quarantines inside that suite.
    static let quarantineKeySuffix = "_unreadable_backup"
    static let quarantineFilePathKeySuffix = "_unreadable_backup_path"

    @Published private(set) var entries: [DictionaryEntry]
    @Published var automaticLearningEnabled: Bool {
        didSet { defaults.set(automaticLearningEnabled, forKey: automaticLearningKey) }
    }

    /// Non-nil when the stored Dictionary could not be read back as written.
    /// Published so the menu bar and Settings can say so — an unreadable
    /// dictionary that nothing reports is indistinguishable, from the user's
    /// seat, from one the app quietly emptied.
    @Published private(set) var storageIncident: DictionaryStorageIncident?

    /// True while the store is refusing to write. `entries` is not the saved
    /// dictionary in this state; it is an empty stand-in, and the real one is
    /// still on disk where it can be recovered.
    var isSavingPaused: Bool { storageIncident?.blocksSaving == true }

    private let defaults: UserDefaults
    private let storageKey: String
    private let migrationKey: String
    private let legacyVocabularyKey: String
    private let automaticLearningKey: String
    private let quarantineDirectory: URL?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "dictionary_entries_v1",
        migrationKey: String = "dictionary_migrated_custom_vocabulary_v1",
        legacyVocabularyKey: String = "custom_vocabulary",
        automaticLearningKey: String = "dictionary_automatic_learning_enabled",
        quarantineDirectory: URL? = DictionaryStore.defaultQuarantineDirectory()
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.migrationKey = migrationKey
        self.legacyVocabularyKey = legacyVocabularyKey
        self.automaticLearningKey = automaticLearningKey
        self.quarantineDirectory = quarantineDirectory
        let loaded = Self.load(from: defaults, key: storageKey, quarantineDirectory: quarantineDirectory)
        self.entries = loaded.entries
        self.storageIncident = loaded.incident
        self.automaticLearningEnabled = defaults.object(forKey: automaticLearningKey) == nil
            ? true
            : defaults.bool(forKey: automaticLearningKey)
        migrateLegacyVocabularyIfNeeded()
        // A wrong-typed value whose bytes still decoded loses nothing, so put
        // the key back to Data now rather than leaving the type mismatch to be
        // rediscovered on every launch. Migration may already have done this;
        // an extra encode of the same entries is cheaper than reasoning about
        // whether it ran.
        if loaded.incident?.blocksSaving == false { persist() }
    }

    /// Gives up on a value that could not be read and starts saving again.
    ///
    /// Deliberately the only way out, and deliberately not reachable from any
    /// automatic path. The refusal in `persist()` is worth nothing if learning,
    /// import or usage counting can lift it on their own, so this is driven
    /// only by the user pressing a button that says what it will do. The
    /// quarantined copy is left exactly where it is — this stays reversible.
    func discardUnreadableStorage() {
        guard isSavingPaused else { return }
        storageIncident = nil
        persist()
        // Skipped at launch so its "done" flag would not be burned against a
        // dictionary nobody could read. Now that the key is writable it can run.
        migrateLegacyVocabularyIfNeeded()
    }

    var activeTerms: [String] {
        entries
            .filter { $0.status == .active && $0.isEnabled }
            .sorted(by: DictionaryEntry.promptRanking)
            .map(\.term)
    }

    /// Projection consumed by the existing newline-delimited vocabulary pipeline.
    var activeTermsText: String { activeTerms.joined(separator: "\n") }

    /// A learned correction the user has confirmed often enough to be worth
    /// offering as a deterministic `word_corrections` rule.
    struct PromotableCorrection: Equatable, Identifiable {
        let heard: String
        let written: String
        let confirmations: Int

        var id: String { heard.lowercased() }
        var ruleLine: String { "\(heard) -> \(written)" }
    }

    /// Hand-edits needed before a correction is offered. An edit is deliberate,
    /// but one can be a slip, and this rule will fire on every future dictation.
    static let promotionThreshold = 2
    static let dismissedPromotionsKey = "dismissed_correction_promotions_v1"

    /// Suggestions the user has turned down. Without this a rejected candidate
    /// is re-offered after every dictation that touches the term, which trains
    /// the user to ignore the list.
    var dismissedPromotions: Set<String> {
        Set(defaults.stringArray(forKey: Self.dismissedPromotionsKey) ?? [])
    }

    func dismissPromotion(_ heard: String) {
        // Same identity the parser and the existing-rule filter use, so a
        // dismissal cannot be evaded by a diacritic.
        let key = TranscriptTidier.CorrectionMapping.identity(ofSpoken: heard)
        guard !key.isEmpty else { return }
        var dismissed = dismissedPromotions
        guard dismissed.insert(key).inserted else { return }
        defaults.set(Array(dismissed).sorted(), forKey: Self.dismissedPromotionsKey)
        objectWillChange.send()
    }

    /// Learned corrections worth offering to the user, best evidence first.
    ///
    /// **This returns suggestions, never an action.** A `word_corrections` rule
    /// rewrites text unconditionally and forever, and the corpus check that
    /// would justify one automatically — "fires >= 2 times with ZERO
    /// counterexamples" — cannot run inside the app: a counterexample is a
    /// dictation where the recogniser got it RIGHT, and until `TranscriptLog`
    /// has accumulated some months there is nothing to count them in. So the
    /// gates here establish *candidacy*, and the user is the gate that matters.
    ///
    /// - Parameter existingSpokenForms: left-hand sides already in the user's
    ///   correction list, so a rule is never offered twice.
    func promotableCorrections(existingSpokenForms: Set<String> = []) -> [PromotableCorrection] {
        let identity = TranscriptTidier.CorrectionMapping.identity(ofSpoken:)
        let blocked = Set(existingSpokenForms.map(identity)).union(dismissedPromotions)
        return entries.compactMap { entry -> PromotableCorrection? in
            guard entry.status != .rejected, entry.isEnabled else { return nil }
            guard let heard = entry.observedSource?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !heard.isEmpty else { return nil }
            let written = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !written.isEmpty else { return nil }
            // Capitalisation is not a mishearing. Entries written before
            // `misheardCount` existed can still carry a case-only
            // `observedSource`, so this is checked here and not only at the
            // point of learning.
            guard heard.lowercased() != written.lowercased() else { return nil }
            // Never offer a pair the rule grammar cannot express. Such a rule
            // would be dropped by the parser on accept, never join the existing
            // set, and therefore be offered again forever.
            guard TranscriptTidier.CorrectionMapping.isRepresentable(spoken: heard, replacement: written)
            else { return nil }
            guard !blocked.contains(identity(heard)) else { return nil }
            // Entries that predate `misheardCount` decode as 0 but still hold
            // proof of one hand-edit in `observedSource`. Credit that one, and
            // no more — their real count is unrecoverable.
            let confirmations = max(entry.misheardCount, 1)
            guard confirmations >= Self.promotionThreshold else { return nil }
            return PromotableCorrection(heard: heard, written: written, confirmations: confirmations)
        }
        .sorted {
            $0.confirmations != $1.confirmations
                ? $0.confirmations > $1.confirmations
                : $0.heard.localizedCaseInsensitiveCompare($1.heard) == .orderedAscending
        }
    }

    @discardableResult
    func addManual(_ term: String, at date: Date = Date()) throws -> DictionaryEntry {
        let term = Self.cleaned(term)
        guard !term.isEmpty else { throw DictionaryStoreError.emptyTerm }

        if let index = index(of: term) {
            guard entries[index].status != .active else {
                throw DictionaryStoreError.duplicateTerm
            }
            entries[index].term = term
            entries[index].source = .manual
            entries[index].status = .active
            entries[index].isEnabled = true
            entries[index].updatedAt = date
            persist()
            return entries[index]
        }

        let entry = DictionaryEntry(
            term: term,
            source: .manual,
            status: .active,
            isEnabled: true,
            observationCount: 0,
            createdAt: date,
            updatedAt: date
        )
        entries.append(entry)
        persist()
        return entry
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isEnabled = enabled
        entries[index].updatedAt = Date()
        persist()
    }

    func setStarred(_ starred: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].starred = starred
        entries[index].updatedAt = Date()
        persist()
    }

    /// Counts which enabled entries a finished dictation actually used, so the
    /// vocabulary ranking favors terms that keep showing up. Called once per
    /// successful dictation with the final pasted transcript; scans enabled
    /// active entries in a single pass and persists at most once.
    func recordUsage(in transcript: String) {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        var didIncrement = false
        for index in entries.indices where entries[index].status == .active && entries[index].isEnabled {
            guard Self.containsWholeWord(entries[index].term, in: transcript) else { continue }
            entries[index].usageCount += 1
            didIncrement = true
        }
        if didIncrement { persist() }
    }

    /// Case- and diacritic-insensitive containment that only matches at word
    /// boundaries, so "AI" never matches inside "maintain".
    static func containsWholeWord(_ term: String, in text: String) -> Bool {
        guard !term.isEmpty else { return false }
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(
                  of: term,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<text.endIndex
              ) {
            let boundedBefore = found.lowerBound == text.startIndex
                || !isWordCharacter(text[text.index(before: found.lowerBound)])
            let boundedAfter = found.upperBound == text.endIndex
                || !isWordCharacter(text[found.upperBound])
            if boundedBefore && boundedAfter { return true }
            searchStart = text.index(after: found.lowerBound)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    func acceptSuggestion(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .active
        entries[index].isEnabled = true
        entries[index].updatedAt = Date()
        persist()
    }

    func dismissSuggestion(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .rejected
        entries[index].isEnabled = false
        entries[index].updatedAt = Date()
        persist()
    }

    /// Records terms proposed by the on-device intelligence layer. A term is
    /// counted at most once per transcript/call, and activates after repeated
    /// observations rather than trusting a one-off recognition mistake.
    func observe(candidateTerms: [String], at date: Date = Date()) {
        guard automaticLearningEnabled else { return }
        let uniqueTerms = Dictionary(grouping: candidateTerms.map(Self.cleaned).filter { !$0.isEmpty }) {
            Self.canonical($0)
        }.compactMap { $0.value.first }

        guard !uniqueTerms.isEmpty else { return }
        let rejected = entries
            .filter { $0.source == .learned && $0.status == .rejected }
            .sorted { $0.updatedAt < $1.updatedAt }
        if rejected.count > Self.learnedEntryLimit {
            let expiredIDs = Set(rejected.prefix(rejected.count - Self.learnedEntryLimit).map(\.id))
            entries.removeAll { expiredIDs.contains($0.id) }
        }
        for term in uniqueTerms {
            if let index = index(of: term) {
                guard entries[index].source == .learned,
                      entries[index].status != .rejected else { continue }
                entries[index].observationCount += 1
                if entries[index].observationCount >= Self.learningThreshold {
                    entries[index].status = .active
                }
                entries[index].updatedAt = date
            } else {
                let learnedEntries = entries.filter { $0.source == .learned && $0.status != .rejected }
                guard learnedEntries.count < Self.learnedEntryLimit,
                      learnedEntries.filter({ $0.status == .suggested }).count < Self.suggestionLimit else {
                    continue
                }
                entries.append(DictionaryEntry(
                    term: term,
                    source: .learned,
                    status: Self.learningThreshold <= 1 ? .active : .suggested,
                    isEnabled: true,
                    observationCount: 1,
                    createdAt: date,
                    updatedAt: date
                ))
            }
        }
        persist()
    }

    /// Records a word the user fixed by hand right after a dictation.
    ///
    /// An explicit edit is much stronger evidence than a term merely appearing
    /// in a transcript, so this needs two sightings rather than
    /// `learningThreshold` — but never fewer, because `DictationEditLearner`
    /// cannot be perfect and one wrong activation biases the recogniser against
    /// the user from then on. A manual entry is never touched.
    ///
    /// Returns the resulting status when something changed, for logging.
    @discardableResult
    func observeEditCorrection(
        _ correction: DictationEditCorrection,
        at date: Date = Date()
    ) -> DictionaryEntry.Status? {
        guard automaticLearningEnabled else { return nil }
        let written = Self.cleaned(correction.written)
        guard !written.isEmpty else { return nil }

        if let index = index(of: written) {
            // Same word already known. A case-only fix is safe to apply
            // immediately: it is not new vocabulary, just the right spelling of
            // a term the user already keeps.
            //
            // Both case-only outcomes return here. Falling through when the
            // term already matched is how five of the six `observedSource`
            // values on this Mac came to be capitalisation pairs — "And"->"and",
            // "send"->"Send", "Like"->"like" — which are not mishearings and
            // must never become deterministic rules. `isCaseOnly` is exactly
            // `heard.lowercased() == written.lowercased()`, so it is the right
            // discriminator and not an approximation of one.
            if correction.isCaseOnly {
                if entries[index].term != written {
                    entries[index].term = written
                    entries[index].updatedAt = date
                    persist()
                }
                return entries[index].status
            }
            guard entries[index].source == .learned,
                  entries[index].status != .rejected else { return nil }
            // Keep the misheard form. Without it a confirmed correction can only
            // ever be a preferred spelling; with it, it can become a
            // deterministic rule. First observation wins, so a later unrelated
            // mishearing of the same word cannot overwrite it.
            if entries[index].observedSource == nil {
                entries[index].observedSource = correction.heard
            }
            // Only the edit path, and only a real mishearing, reaches this —
            // and only when the mishearing is the SAME one already recorded.
            //
            // `misheardCount` is stored per term but the pair it will be
            // promoted as is (observedSource -> term), and observedSource is
            // first-wins. Counting every correction of the term would let two
            // DIFFERENT mishearings satisfy the two-confirmation gate for a
            // pair that only ever occurred once: "beta -> alpha" followed by
            // "gamma -> alpha" would offer `beta -> alpha` with 2
            // confirmations. A second distinct mishearing is deliberately not
            // tracked at all; it is not evidence for this pair.
            if let recorded = entries[index].observedSource,
               TranscriptTidier.CorrectionMapping.identity(ofSpoken: recorded)
                   == TranscriptTidier.CorrectionMapping.identity(ofSpoken: correction.heard) {
                entries[index].misheardCount += 1
            }
            entries[index].observationCount += 1
            if entries[index].observationCount >= Self.editLearningThreshold {
                entries[index].status = .active
            }
            entries[index].updatedAt = date
            persist()
            return entries[index].status
        }

        let learnedEntries = entries.filter { $0.source == .learned && $0.status != .rejected }
        guard learnedEntries.count < Self.learnedEntryLimit,
              learnedEntries.filter({ $0.status == .suggested }).count < Self.suggestionLimit else {
            return nil
        }
        entries.append(DictionaryEntry(
            term: written,
            source: .learned,
            status: Self.editLearningThreshold <= 1 ? .active : .suggested,
            isEnabled: true,
            observationCount: 1,
            createdAt: date,
            updatedAt: date,
            // A case-only fix on a term that is new to the dictionary is still
            // only capitalisation. Record the term, never the "mishearing".
            observedSource: correction.isCaseOnly ? nil : correction.heard,
            misheardCount: correction.isCaseOnly ? 0 : 1
        ))
        persist()
        return Self.editLearningThreshold <= 1 ? .active : .suggested
    }

    func exportDocument(exactCorrections: String, exportedAt: Date = Date()) -> DictionaryExportDocument {
        DictionaryExportDocument(entries: entries, exactCorrections: exactCorrections, exportedAt: exportedAt)
    }

    /// Merges entries from an exported Dictionary file; nothing local is ever
    /// removed. Terms match case- and diacritic-insensitively. An imported
    /// active entry re-activates a local suggestion or rejection (the other
    /// machine's explicit teaching wins), while an imported suggestion never
    /// overrides a local rejection. Counters keep the larger value so ranking
    /// survives the move. Learned additions respect the usual limits.
    @discardableResult
    func importEntries(_ imported: [DictionaryEntry], at date: Date = Date()) -> DictionaryImportResult {
        var result = DictionaryImportResult()
        var didChange = false
        for entry in imported {
            let term = Self.cleaned(entry.term)
            guard !term.isEmpty else { continue }
            if let index = index(of: term) {
                let before = entries[index]
                var local = before
                if entry.status == .active && local.status != .active {
                    local.status = .active
                    local.isEnabled = entry.isEnabled
                }
                if entry.source == .manual { local.source = .manual }
                local.starred = local.starred || entry.starred
                local.observationCount = max(local.observationCount, entry.observationCount)
                local.usageCount = max(local.usageCount, entry.usageCount)
                guard local != before else { continue }
                if local.status != before.status || local.source != before.source
                    || local.starred != before.starred || local.isEnabled != before.isEnabled {
                    result.updatedCount += 1
                }
                local.updatedAt = date
                entries[index] = local
                didChange = true
            } else {
                if entry.source == .learned && entry.status != .rejected {
                    let learned = entries.filter { $0.source == .learned && $0.status != .rejected }
                    guard learned.count < Self.learnedEntryLimit else { continue }
                    if entry.status == .suggested,
                       learned.filter({ $0.status == .suggested }).count >= Self.suggestionLimit {
                        continue
                    }
                }
                entries.append(DictionaryEntry(
                    term: term,
                    source: entry.source,
                    status: entry.status,
                    isEnabled: entry.isEnabled,
                    observationCount: entry.observationCount,
                    starred: entry.starred,
                    usageCount: entry.usageCount,
                    createdAt: entry.createdAt,
                    updatedAt: date
                ))
                // Imported rejections still suppress future suggestions, but
                // they are invisible in the UI, so don't count them as added.
                if entry.status != .rejected { result.addedCount += 1 }
                didChange = true
            }
        }
        if didChange { persist() }
        return result
    }

    /// Appends imported "heard → wanted" correction lines that aren't already
    /// present locally (compared case-insensitively), preserving local order
    /// and leaving local lines untouched.
    static func mergedCorrections(local: String, imported: String) -> (text: String, addedCount: Int) {
        func normalized(_ line: String) -> String {
            line.trimmingCharacters(in: .whitespaces).lowercased()
        }
        var seen = Set(local.components(separatedBy: "\n").map(normalized).filter { !$0.isEmpty })
        var appended: [String] = []
        for line in imported.components(separatedBy: "\n") {
            let key = normalized(line)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            appended.append(line.trimmingCharacters(in: .whitespaces))
        }
        guard !appended.isEmpty else { return (local, 0) }
        let trimmedLocal = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmedLocal.isEmpty
            ? appended.joined(separator: "\n")
            : trimmedLocal + "\n" + appended.joined(separator: "\n")
        return (text, appended.count)
    }

    private func migrateLegacyVocabularyIfNeeded() {
        guard !defaults.bool(forKey: migrationKey) else { return }
        // Bail before the flag is written. With the stored dictionary unreadable
        // there is no way to know which of these terms it already holds, and
        // recording the migration as done would skip it for good once the value
        // is repaired. The append below would also leave `entries` looking
        // populated while the real dictionary is still unread.
        guard !isSavingPaused else { return }
        let legacy = defaults.string(forKey: legacyVocabularyKey) ?? ""
        let terms = legacy
            .components(separatedBy: CharacterSet(charactersIn: "\n,;"))
            .map(Self.cleaned)
            .filter { !$0.isEmpty }

        let now = Date()
        for term in terms where index(of: term) == nil {
            entries.append(DictionaryEntry(
                term: term,
                source: .manual,
                status: .active,
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            ))
        }
        persist()
        defaults.set(true, forKey: migrationKey)
    }

    private func index(of term: String) -> Int? {
        let canonicalTerm = Self.canonical(term)
        return entries.firstIndex { Self.canonical($0.term) == canonicalTerm }
    }

    private func persist() {
        // The 2026-08-07 loss went through this line. `load` could not read the
        // stored value, handed back `[]`, and the next learned term wrote four
        // entries over 322. Every mutator on this class funnels through here —
        // add, remove, enable, star, usage, accept, dismiss, observe, edit,
        // import, migrate — so the refusal belongs here and not at the sixteen
        // call sites, one of which would eventually be added without it.
        guard !isSavingPaused else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private struct LoadResult {
        var entries: [DictionaryEntry]
        var incident: DictionaryStorageIncident?
    }

    /// Reads the stored dictionary, keeping the three outcomes apart.
    ///
    /// The old version collapsed two of them: `data(forKey:)` answers nil both
    /// when nothing was ever written and when a value is there but is not Data,
    /// so it returned `[]` for both. One of those is a first run, which is
    /// correctly empty and writable. The other is a dictionary that is still on
    /// disk, and treating it as the first cost 322 entries.
    private static func load(
        from defaults: UserDefaults,
        key: String,
        quarantineDirectory: URL?
    ) -> LoadResult {
        guard let stored = defaults.object(forKey: key) else {
            // Nothing has ever been written. The only case allowed to come up
            // empty *and* writable.
            return LoadResult(entries: [], incident: nil)
        }

        if let data = stored as? Data {
            if let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
                return LoadResult(entries: decoded, incident: nil)
            }
            return LoadResult(entries: [], incident: quarantine(
                stored,
                reason: .undecodable(byteCount: data.count),
                blocksSaving: true,
                in: defaults,
                key: key,
                directory: quarantineDirectory
            ))
        }

        // Not Data. If it is text that still carries the JSON, the words are
        // intact and only the type is wrong — take them, and let the write
        // below put the key back. This is the shape the 2026-08-07 value had,
        // and salvaging it is the difference between an incident and a
        // non-event. It cannot fire spuriously: every key of `DictionaryEntry`
        // except the three added later is required, so no stray string decodes.
        if let text = stored as? String,
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: Data(text.utf8)) {
            return LoadResult(entries: decoded, incident: quarantine(
                stored,
                reason: .wrongType(described: describe(stored)),
                blocksSaving: false,
                in: defaults,
                key: key,
                directory: quarantineDirectory
            ))
        }

        return LoadResult(entries: [], incident: quarantine(
            stored,
            reason: .wrongType(described: describe(stored)),
            blocksSaving: true,
            in: defaults,
            key: key,
            directory: quarantineDirectory
        ))
    }

    /// Keeps the bytes that could not be read, so getting the words back does
    /// not depend on an unrelated backup happening to exist — which is the only
    /// reason the 2026-08-07 loss was recoverable at all.
    ///
    /// First failure wins. If a copy is already parked, it is left alone and
    /// nothing new is written: the oldest copy is the one closest to the last
    /// good dictionary, and a relaunch loop must not push it out.
    private static func quarantine(
        _ stored: Any,
        reason: DictionaryStorageIncident.Reason,
        blocksSaving: Bool,
        in defaults: UserDefaults,
        key: String,
        directory: URL?
    ) -> DictionaryStorageIncident {
        let quarantineKey = key + quarantineKeySuffix
        let pathKey = key + quarantineFilePathKeySuffix
        var fileURL: URL?

        if defaults.object(forKey: quarantineKey) == nil {
            // Whatever came out of `object(forKey:)` is a property-list type by
            // construction, so it can always go back in as one.
            defaults.set(stored, forKey: quarantineKey)
            fileURL = writeQuarantineFile(stored, key: key, directory: directory)
            if let fileURL { defaults.set(fileURL.path, forKey: pathKey) }
        } else if let existingPath = defaults.string(forKey: pathKey) {
            fileURL = URL(fileURLWithPath: existingPath)
        }

        return DictionaryStorageIncident(
            reason: reason,
            blocksSaving: blocksSaving,
            quarantineKey: quarantineKey,
            quarantineFileURL: fileURL
        )
    }

    private static func writeQuarantineFile(_ stored: Any, key: String, directory: URL?) -> URL? {
        guard let directory else { return nil }
        let payload: Data?
        switch stored {
        case let data as Data: payload = data
        case let text as String: payload = Data(text.utf8)
        default: payload = try? PropertyListSerialization.data(
            fromPropertyList: stored, format: .xml, options: 0
        )
        }
        guard let payload else { return nil }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        stamp.timeZone = TimeZone(identifier: "UTC")
        stamp.locale = Locale(identifier: "en_US_POSIX")
        // The timestamp is only to seconds, so two incidents inside one second
        // would land on the same name and the second would erase the first —
        // measured, not hypothetical: five corruptions in one harness run wrote
        // a single file. A copy that another copy can delete is not a copy.
        let base = "\(key)-unreadable-\(stamp.string(from: Date()))"
        var url = directory.appendingPathComponent("\(base).bin", isDirectory: false)
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path), attempt <= 100 {
            url = directory.appendingPathComponent("\(base)-\(attempt).bin", isDirectory: false)
            attempt += 1
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try payload.write(to: url, options: .atomic)
            return url
        } catch {
            // Best effort. The sibling defaults key already holds the value, and
            // a failure to write here must never stop the store reporting the
            // fault — reporting it is the part that was missing.
            return nil
        }
    }

    /// Same folder the transcript log uses.
    static func defaultQuarantineDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Megaphone", isDirectory: true)
    }

    /// Plain words rather than `type(of:)`, whose answer for a bridged
    /// preference value is `__NSCFString` and tells the user nothing.
    private static func describe(_ value: Any) -> String {
        switch value {
        case is String: return "text"
        case is NSNumber: return "a number"
        case is Date: return "a date"
        case is [Any]: return "a list"
        case is [String: Any]: return "a group of settings"
        default: return "an unexpected kind of value"
        }
    }

    static func cleaned(_ term: String) -> String {
        let collapsed = term
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return strippingSentencePunctuation(collapsed)
    }

    /// A word that ended a sentence was being learned with its full stop
    /// attached — 25 such entries had accumulated ("Slack.", "Friday.", "August."),
    /// 12 of them duplicating a clean entry that already existed.
    ///
    /// A trailing full stop is only removed when the rest of the term has none,
    /// so "CLAUDE.md" and "e.g." survive intact while "MD." does not.
    static func strippingSentencePunctuation(_ term: String) -> String {
        var result = term
        while let last = result.last, ",;:!?".contains(last) {
            result.removeLast()
        }
        if result.last == ".", !result.dropLast().contains(".") {
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func canonical(_ term: String) -> String {
        cleaned(term).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum DictionaryTermLearner {
    private static let commonWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "for",
        "from", "had", "has", "have", "he", "her", "here", "his", "how", "i", "if",
        "in", "is", "it", "its", "just", "me", "my", "no", "not", "of", "on", "or",
        "our", "please", "she", "so", "that", "the", "their", "them", "then", "there",
        "they", "this", "to", "up", "us", "was", "we", "were", "what", "when", "where",
        "which", "who", "will", "with", "would", "yes", "you", "your"
    ]

    /// Finds conservative names and technical tokens worth observing. A
    /// candidate still needs three separate successful dictations before the
    /// store activates it, so this intentionally favors precision over recall.
    static func candidates(from transcript: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[\p{L}\p{N}][\p{L}\p{N}'’._+-]{1,63}"#
        ) else { return [] }

        let nsTranscript = transcript as NSString
        let matches = regex.matches(
            in: transcript,
            range: NSRange(location: 0, length: nsTranscript.length)
        )

        return matches.compactMap { match in
            let term = nsTranscript.substring(with: match.range)
            let folded = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !commonWords.contains(folded),
                  !term.contains("@"),
                  !term.lowercased().hasPrefix("http") else { return nil }

            let letters = term.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            guard !letters.isEmpty else { return nil }
            let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
            let lowercaseCount = letters.filter { CharacterSet.lowercaseLetters.contains($0) }.count
            let hasNumber = term.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            let hasTechnicalSeparator = term.contains("-") || term.contains("_") || term.contains("+")
            let isAcronym = uppercaseCount >= 2 && lowercaseCount == 0
            let hasInternalCapital = term.dropFirst().unicodeScalars.contains {
                CharacterSet.uppercaseLetters.contains($0)
            }

            // Capitalized words away from a sentence boundary are likely
            // proper names. Sentence-initial capitalization alone is weak.
            let prefix = nsTranscript.substring(to: match.range.location)
            let prior = prefix.trimmingCharacters(in: .whitespacesAndNewlines).last
            let isSentenceInitial = prior == nil || ".!?".contains(prior!)
            let isMidSentenceName = uppercaseCount >= 1 && !isSentenceInitial

            guard isAcronym || hasInternalCapital || hasNumber || hasTechnicalSeparator || isMidSentenceName else {
                return nil
            }
            return term
        }
    }
}
