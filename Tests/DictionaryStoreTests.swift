import Foundation

enum DictionaryStoreTests {
    static func run() {
        testLearnedTermsLoseSentencePunctuation()
        testManualTermsAndProjection()
        testConservativeLearning()
        testAutomaticLearningToggle()
        testManualEntryPromotesSuggestion()
        testLegacyMigrationRunsOnce()
        testPersistence()
        testConservativeCandidateExtraction()
        testDismissedSuggestionStaysDismissed()
        testDecodesEntriesStoredBeforeRanking()
        testPromptRankingOrder()
        testUsageMatchingRespectsWordBoundaries()
        testUsageIncrementsOnlyEnabledEntries()
        testStarAndUsagePersist()
        testExportDocumentRoundTrip()
        testImportMergesByTerm()
        testImportPersists()
        testMergedCorrections()
        testEditCorrectionsNeedTwoSightings()
        testEditCaseFixAppliesImmediately()
        testEditCorrectionRespectsRejectionAndManual()
        testLearningRecordsTheMishearThatCausedIt()
        testMisheardCountIsNotBumpedByTheRecogniserBeingRight()
        testCaseOnlyFixesAreNeverMishearEvidence()
        testPromotionNeedsTwoConfirmations()
        testPromotionSkipsRulesTheUserAlreadyHas()
        testDismissedPromotionStaysDismissed()
        testLegacyEntriesCountAsOneConfirmationOnly()
        testTwoDifferentMishearsDoNotConfirmOnePair()
        testUnrepresentablePairsAreNeverOffered()
        testExistingRuleBlockingFoldsDiacritics()
        testAbsentKeyIsAFirstRunAndStaysWritable()
        testValidStoredDictionaryStillLoads()
        testWrongTypedValueIsNeverOverwritten()
        testGarbageDataIsNeverOverwritten()
        testWrongTypedValueThatStillHoldsTheJSONIsRecovered()
        testUnreadableValueIsKeptForRecovery()
        testUnreadableValueDoesNotBurnTheLegacyMigration()
        testDiscardIsTheOnlyWayToResumeSaving()
    }

    // MARK: - Unreadable storage
    //
    // 2026-08-07: `dictionary_entries_v1` came back as a String where Data
    // belongs. `data(forKey:)` answers nil for that exactly as it does for a
    // key that was never written, so the store came up empty AND writable, and
    // four freshly-learned terms were persisted over 322. These cover the four
    // states the loader has to keep apart, and — the actual regression — that a
    // value it cannot read is never written over.

    /// The case that must stay boring. No stored value at all is a first run:
    /// empty dictionary, no incident, saving works from the first word.
    private static func testAbsentKeyIsAFirstRunAndStaysWritable() {
        let (suite, defaults, directory) = makeIsolatedStorage()
        defer { destroy(suite: suite, defaults: defaults, directory: directory) }

        let store = makeStore(defaults, directory)
        expectEqual(store.entries.isEmpty, true)
        expectEqual(store.storageIncident, nil)
        expectEqual(store.isSavingPaused, false)

        _ = try! store.addManual("Kestrel")
        let reloaded = makeStore(defaults, directory)
        expectEqual(reloaded.activeTerms, ["Kestrel"])
        expectEqual(reloaded.storageIncident, nil)
        // Nothing was quarantined, because nothing was wrong.
        expectEqual(defaults.object(forKey: "entries" + DictionaryStore.quarantineKeySuffix) == nil, true)
    }

    /// The other case that must stay boring: a real stored dictionary loads,
    /// reports no incident, and keeps saving.
    private static func testValidStoredDictionaryStillLoads() {
        let (suite, defaults, directory) = makeIsolatedStorage()
        defer { destroy(suite: suite, defaults: defaults, directory: directory) }

        let seed = makeStore(defaults, directory)
        _ = try! seed.addManual("Kestrel")
        _ = try! seed.addManual("LedgerIQ")

        let reloaded = makeStore(defaults, directory)
        expectEqual(reloaded.activeTerms, ["Kestrel", "LedgerIQ"])
        expectEqual(reloaded.storageIncident, nil)
        expectEqual(reloaded.isSavingPaused, false)
        _ = try! reloaded.addManual("Whitfield")
        expectEqual(makeStore(defaults, directory).activeTerms.count, 3)
    }

    /// The regression itself. A String where Data belongs must not read as a
    /// first run, and the session's learning must be dropped rather than
    /// written over a dictionary that is still sitting there.
    private static func testWrongTypedValueIsNeverOverwritten() {
        let (suite, defaults, directory) = makeIsolatedStorage()
        defer { destroy(suite: suite, defaults: defaults, directory: directory) }

        // Not the JSON — a value that carries no recoverable entries, which is
        // the case where refusing to write is the only thing protecting them.
        defaults.set("dictionary_entries_v1", forKey: "entries")
        let store = makeStore(defaults, directory)

        expectEqual(store.entries.isEmpty, true)
        expectEqual(store.isSavingPaused, true)
        expectEqual(store.storageIncident?.reason, DictionaryStorageIncident.Reason.wrongType(described: "text"))

        // Every path that writes, exercised against the guard in one place.
        store.observe(candidateTerms: ["Kestrel"])
        store.observe(candidateTerms: ["Kestrel"])
        store.observe(candidateTerms: ["Kestrel"])
        _ = try? store.addManual("Whitfield")
        store.observeEditCorrection(
            DictationEditCorrection(heard: "Merrick", written: "Marek", isCaseOnly: false)
        )
        store.importEntries([DictionaryEntry(term: "Trelawney", source: .manual, status: .active)])
        store.recordUsage(in: "Kestrel and Whitfield")
        if let first = store.entries.first {
            store.setStarred(true, for: first.id)
            store.setEnabled(false, for: first.id)
            store.acceptSuggestion(id: first.id)
            store.dismissSuggestion(id: first.id)
            store.remove(id: first.id)
        }

        expectEqual(defaults.string(forKey: "entries"), "dictionary_entries_v1")
        expectEqual(defaults.data(forKey: "entries") == nil, true)
    }

    /// Same protection when the value IS Data but the bytes are damaged — a
    /// half-written or truncated blob decodes to nothing and must be left alone.
    private static func testGarbageDataIsNeverOverwritten() {
        for corrupt in [
            Data(#"[{"id":"7B1C"#.utf8),                    // truncated mid-entry
            Data([0x00, 0xFF, 0x10, 0x82, 0x5A]),           // not text at all
            Data(#"{"term":"Kestrel"}"#.utf8),              // valid JSON, wrong shape
        ] {
            let (suite, defaults, directory) = makeIsolatedStorage()
            defer { destroy(suite: suite, defaults: defaults, directory: directory) }

            defaults.set(corrupt, forKey: "entries")
            let store = makeStore(defaults, directory)

            expectEqual(store.entries.isEmpty, true)
            expectEqual(store.isSavingPaused, true)
            expectEqual(
                store.storageIncident?.reason,
                DictionaryStorageIncident.Reason.undecodable(byteCount: corrupt.count)
            )

            store.observe(candidateTerms: ["Kestrel"])
            store.observe(candidateTerms: ["Kestrel"])
            store.observe(candidateTerms: ["Kestrel"])
            _ = try? store.addManual("Whitfield")
            expectEqual(defaults.data(forKey: "entries"), corrupt)
        }
    }

    /// A wrong-typed value whose bytes still hold the JSON loses nothing, so
    /// the words come back and the key is put right instead of being frozen.
    private static func testWrongTypedValueThatStillHoldsTheJSONIsRecovered() {
        let (suite, defaults, directory) = makeIsolatedStorage()
        defer { destroy(suite: suite, defaults: defaults, directory: directory) }

        let seed = makeStore(defaults, directory)
        _ = try! seed.addManual("Kestrel")
        _ = try! seed.addManual("LedgerIQ")
        let good = defaults.data(forKey: "entries")!

        // Exactly the corruption: the same bytes, stored as a String.
        defaults.set(String(data: good, encoding: .utf8)!, forKey: "entries")
        let store = makeStore(defaults, directory)

        expectEqual(store.activeTerms, ["Kestrel", "LedgerIQ"])
        expectEqual(store.isSavingPaused, false)
        expectEqual(store.storageIncident?.blocksSaving, false)
        // The type mismatch is repaired at load, not left to be rediscovered.
        expectEqual(defaults.data(forKey: "entries") != nil, true)
        expectEqual(makeStore(defaults, directory).activeTerms, ["Kestrel", "LedgerIQ"])
        // And the original is still kept, in case the salvage was wrong.
        expectEqual(
            defaults.string(forKey: "entries" + DictionaryStore.quarantineKeySuffix),
            String(data: good, encoding: .utf8)
        )
    }

    /// Recovery must not depend on an unrelated backup happening to exist —
    /// that is the only reason 2026-08-07 was survivable.
    private static func testUnreadableValueIsKeptForRecovery() {
        let (suite, defaults, directory) = makeIsolatedStorage()
        defer { destroy(suite: suite, defaults: defaults, directory: directory) }

        defaults.set("something that is not a dictionary", forKey: "entries")
        let store = makeStore(defaults, directory)

        let incident = store.storageIncident!
        expectEqual(incident.quarantineKey, "entries" + DictionaryStore.quarantineKeySuffix)
        expectEqual(
            defaults.string(forKey: incident.quarantineKey),
            "something that is not a dictionary"
        )
        let fileURL = incident.quarantineFileURL!
        expectEqual(
            try! String(contentsOf: fileURL, encoding: .utf8),
            "something that is not a dictionary"
        )
        // The message has to name both, or the copy might as well not exist.
        expect(incident.detail.contains(incident.quarantineKey), "Recovery key is not in the message")
        expect(incident.detail.contains(fileURL.path), "Recovery file is not in the message")

        // A relaunch loop must not push the first copy out with a later one.
        defaults.set("a second, different corruption", forKey: "entries")
        let relaunched = makeStore(defaults, directory)
        expectEqual(relaunched.isSavingPaused, true)
        expectEqual(
            defaults.string(forKey: incident.quarantineKey),
            "something that is not a dictionary"
        )
        expectEqual(relaunched.storageIncident?.quarantineFileURL, fileURL)
    }

    /// The migration flag is one-way. Setting it while the dictionary cannot be
    /// read would skip the legacy import for good once the value is repaired.
    private static func testUnreadableValueDoesNotBurnTheLegacyMigration() {
        let (suite, defaults, directory) = makeIsolatedStorage()
        defer { destroy(suite: suite, defaults: defaults, directory: directory) }

        defaults.set("Kestrel\nLedgerIQ", forKey: "legacy")
        defaults.set("not a dictionary", forKey: "entries")

        let blocked = makeStore(defaults, directory)
        expectEqual(blocked.entries.isEmpty, true)
        expectEqual(defaults.bool(forKey: "migrated"), false)

        // Once the value is dealt with, the migration that was skipped runs.
        blocked.discardUnreadableStorage()
        expectEqual(Set(blocked.activeTerms), Set(["Kestrel", "LedgerIQ"]))
        expectEqual(defaults.bool(forKey: "migrated"), true)
        expectEqual(Set(makeStore(defaults, directory).activeTerms), Set(["Kestrel", "LedgerIQ"]))
    }

    /// Saving resumes only on a deliberate, user-driven discard — never as a
    /// side effect of the app carrying on with its day.
    private static func testDiscardIsTheOnlyWayToResumeSaving() {
        let (suite, defaults, directory) = makeIsolatedStorage()
        defer { destroy(suite: suite, defaults: defaults, directory: directory) }

        defaults.set("not a dictionary", forKey: "entries")
        let store = makeStore(defaults, directory)

        // Toggling automatic learning writes its own key; it must not clear this.
        store.automaticLearningEnabled = false
        store.automaticLearningEnabled = true
        store.dismissPromotion("merrick")
        _ = store.exportDocument(exactCorrections: "")
        _ = store.promotableCorrections()
        expectEqual(store.isSavingPaused, true)
        expectEqual(defaults.string(forKey: "entries"), "not a dictionary")

        store.discardUnreadableStorage()
        expectEqual(store.isSavingPaused, false)
        expectEqual(store.storageIncident, nil)
        _ = try! store.addManual("Kestrel")
        expectEqual(makeStore(defaults, directory).activeTerms, ["Kestrel"])
        // The quarantined copy survives the discard — it is the way back.
        expectEqual(
            defaults.string(forKey: "entries" + DictionaryStore.quarantineKeySuffix),
            "not a dictionary"
        )
    }

    /// A defaults suite and a quarantine folder that are this test's alone, so
    /// nothing here can reach the installed app's preferences or its
    /// Application Support folder.
    private static func makeIsolatedStorage() -> (String, UserDefaults, URL) {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite, isDirectory: true)
        return (suite, UserDefaults(suiteName: suite)!, directory)
    }

    private static func makeStore(_ defaults: UserDefaults, _ directory: URL) -> DictionaryStore {
        DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy",
            quarantineDirectory: directory
        )
    }

    private static func destroy(suite: String, defaults: UserDefaults, directory: URL) {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    /// `misheardCount` lives on the term but the pair it promotes as is
    /// (observedSource -> term), and observedSource is first-wins. Two
    /// DIFFERENT mishearings must not jointly satisfy the gate for a pair that
    /// only happened once.
    private static func testTwoDifferentMishearsDoNotConfirmOnePair() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        store.observeEditCorrection(DictationEditCorrection(heard: "beta", written: "alpha", isCaseOnly: false))
        store.observeEditCorrection(DictationEditCorrection(heard: "gamma", written: "alpha", isCaseOnly: false))

        guard let entry = store.entries.first(where: { $0.term == "alpha" }) else {
            fatalError("entry missing")
        }
        expectEqual(entry.observedSource, "beta")   // first wins
        expectEqual(entry.misheardCount, 1)         // gamma is not evidence for beta->alpha
        expectEqual(store.promotableCorrections().isEmpty, true)

        // The same mishearing again DOES confirm it.
        store.observeEditCorrection(DictationEditCorrection(heard: "beta", written: "alpha", isCaseOnly: false))
        expectEqual(store.promotableCorrections().first?.heard, "beta")
    }

    /// The rule grammar is line-oriented and has no escapes. A pair it cannot
    /// express must never be offered — accepting it would either do nothing
    /// (and be re-offered forever) or install a rule the user never saw.
    private static func testUnrepresentablePairsAreNeverOffered() {
        // Only pairs that can actually reach the store. `Self.cleaned` collapses
        // whitespace on the WRITTEN side, so a newline can never survive there —
        // but `observedSource` keeps the heard side verbatim, which is exactly
        // where recogniser output arrives. The full character matrix is tested
        // against `isRepresentable` directly in TranscriptTidierTests.
        for (heard, written) in [
            ("ht\nmo", "HTML"),     // would append a live `mo -> HTML`
            ("a -> b", "HTML"),     // three components, silently dropped
            ("htmo", "A -> B"),
            ("a => b", "HTML"),
            ("a \u{2192} b", "HTML"),
            ("#tag", "HTML"),       // becomes a comment
        ] {
            let (store, defaults) = makeStore()
            defer { clear(defaults) }
            let fix = DictationEditCorrection(heard: heard, written: written, isCaseOnly: false)
            store.observeEditCorrection(fix)
            store.observeEditCorrection(fix)
            expectEqual(store.promotableCorrections().isEmpty, true)
        }
    }

    /// `parse` dedupes case- AND diacritic-insensitively, so the existing-rule
    /// filter has to as well or it offers a duplicate the parser then discards.
    private static func testExistingRuleBlockingFoldsDiacritics() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let fix = DictationEditCorrection(heard: "cafe\u{301}", written: "coffee", isCaseOnly: false)
        store.observeEditCorrection(fix)
        store.observeEditCorrection(fix)
        expectEqual(store.promotableCorrections().isEmpty, false)
        // An existing rule spelled without the accent must block it.
        expectEqual(store.promotableCorrections(existingSpokenForms: ["CAFE"]).isEmpty, true)
    }

    /// The whole reason `misheardCount` exists. `observationCount` is bumped by
    /// `observe(candidateTerms:)` on every successful dictation containing the
    /// term, so a gate reading it is satisfied by the recogniser being RIGHT.
    private static func testMisheardCountIsNotBumpedByTheRecogniserBeingRight() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let fix = DictationEditCorrection(heard: "htmo", written: "HTML", isCaseOnly: false)
        store.observeEditCorrection(fix)
        store.observe(candidateTerms: ["HTML"])
        store.observe(candidateTerms: ["HTML"])
        store.observe(candidateTerms: ["HTML"])

        guard let entry = store.entries.first(where: { $0.term == "HTML" }) else {
            fatalError("entry was not learned")
        }
        expectEqual(entry.misheardCount, 1)
        // The old counter really does climb on success — this asserts the two
        // fields have genuinely diverged rather than both being unused.
        expectEqual(entry.observationCount > entry.misheardCount, true)
    }

    /// Five of the six `observedSource` values on the real Mac were
    /// capitalisation pairs, because the case-only branch fell through when the
    /// term already matched. "And" -> "and" must never become a rule.
    private static func testCaseOnlyFixesAreNeverMishearEvidence() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        // Term not yet known.
        store.observeEditCorrection(DictationEditCorrection(heard: "And", written: "and", isCaseOnly: true))
        // Term now known AND already spelled that way — the fall-through case.
        store.observeEditCorrection(DictationEditCorrection(heard: "And", written: "and", isCaseOnly: true))

        guard let entry = store.entries.first(where: { $0.term == "and" }) else {
            fatalError("case-only entry missing")
        }
        expectEqual(entry.observedSource, nil)
        expectEqual(entry.misheardCount, 0)
        expectEqual(store.promotableCorrections().isEmpty, true)
    }

    private static func testPromotionNeedsTwoConfirmations() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let fix = DictationEditCorrection(heard: "htmo", written: "HTML", isCaseOnly: false)
        store.observeEditCorrection(fix)
        expectEqual(store.promotableCorrections().isEmpty, true)

        store.observeEditCorrection(fix)
        let promotable = store.promotableCorrections()
        expectEqual(promotable.count, 1)
        expectEqual(promotable.first?.heard, "htmo")
        expectEqual(promotable.first?.written, "HTML")
        expectEqual(promotable.first?.ruleLine, "htmo -> HTML")
    }

    private static func testPromotionSkipsRulesTheUserAlreadyHas() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let fix = DictationEditCorrection(heard: "htmo", written: "HTML", isCaseOnly: false)
        store.observeEditCorrection(fix)
        store.observeEditCorrection(fix)
        // Case-insensitive: the correction list matches case-insensitively too.
        expectEqual(store.promotableCorrections(existingSpokenForms: ["HTMO"]).isEmpty, true)
    }

    private static func testDismissedPromotionStaysDismissed() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let fix = DictationEditCorrection(heard: "htmo", written: "HTML", isCaseOnly: false)
        store.observeEditCorrection(fix)
        store.observeEditCorrection(fix)
        expectEqual(store.promotableCorrections().count, 1)

        store.dismissPromotion("HTMO")
        expectEqual(store.promotableCorrections().isEmpty, true)
        // Another confirmation must not resurrect it.
        store.observeEditCorrection(fix)
        expectEqual(store.promotableCorrections().isEmpty, true)
    }

    /// Entries written before `misheardCount` existed decode as 0 but still
    /// prove one hand-edit. Credit exactly one — their real count is gone.
    private static func testLegacyEntriesCountAsOneConfirmationOnly() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        // Hand-built so the key is genuinely ABSENT. Encoding a DictionaryEntry
        // would emit "misheardCount":0 and never exercise `decodeIfPresent`,
        // so the test would pass even with back-compat broken.
        let json = """
        [{"id":"\(UUID().uuidString)","term":"HTML","source":"learned","status":"active",
          "isEnabled":true,"observationCount":14,"starred":false,"usageCount":0,
          "createdAt":0,"updatedAt":0,"observedSource":"HTMO"}]
        """
        let data = Data(json.utf8)
        expectEqual(String(data: data, encoding: .utf8)!.contains("misheardCount"), false)
        defaults.set(data, forKey: "entries")
        let reloaded = DictionaryStore(
            defaults: defaults, storageKey: "entries",
            migrationKey: "migrated", legacyVocabularyKey: "legacy"
        )
        // One confirmation, and the threshold is two — so it waits for the next
        // real edit rather than trusting a count it cannot verify.
        expectEqual(reloaded.entries.first?.misheardCount, 0)
        expectEqual(reloaded.promotableCorrections().isEmpty, true)
    }

    /// An edit is stronger evidence than a transcript sighting, but still not
    /// enough on its own: first edit suggests, second activates.
    private static func testEditCorrectionsNeedTwoSightings() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let fix = DictationEditCorrection(heard: "get", written: "git", isCaseOnly: false)
        expectEqual(store.observeEditCorrection(fix), .suggested)
        expectEqual(store.activeTerms.contains("git"), false)   // not biasing anything yet
        expectEqual(store.observeEditCorrection(fix), .active)
        expectEqual(store.activeTerms.contains("git"), true)
    }

    /// Recasing a term the user already keeps is not new vocabulary, so it
    /// applies at once rather than waiting for a second sighting.
    private static func testEditCaseFixAppliesImmediately() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("claude")
        expectEqual(store.activeTerms, ["claude"])
        _ = store.observeEditCorrection(
            DictationEditCorrection(heard: "claude", written: "Claude", isCaseOnly: true)
        )
        expectEqual(store.activeTerms, ["Claude"])
    }

    private static func testEditCorrectionRespectsRejectionAndManual() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        // A term the user rejected must never come back through the edit path.
        let fix = DictationEditCorrection(heard: "kuber", written: "Kuber", isCaseOnly: false)
        _ = store.observeEditCorrection(fix)
        let suggestion = store.entries.first { $0.term == "Kuber" }!
        store.dismissSuggestion(id: suggestion.id)
        expectEqual(store.observeEditCorrection(fix), nil)
        expectEqual(store.activeTerms.contains("Kuber"), false)

        // A manual entry's observation count is not touched by edits.
        _ = try! store.addManual("Supabase")
        expectEqual(
            store.observeEditCorrection(
                DictationEditCorrection(heard: "supabase", written: "Supabase", isCaseOnly: false)
            ),
            nil
        )
    }

    private static func testManualTermsAndProjection() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let first = try! store.addManual("  Megaphone  ")
        _ = try! store.addManual("SpeechAnalyzer")
        expectEqual(store.activeTerms, ["Megaphone", "SpeechAnalyzer"])
        store.setEnabled(false, for: first.id)
        expectEqual(store.activeTermsText, "SpeechAnalyzer")
        expectThrows(.duplicateTerm) { try store.addManual("megaphone") }
        expectThrows(.emptyTerm) { try store.addManual("   ") }
    }

    private static func testConservativeLearning() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        store.observe(candidateTerms: ["Kuber", "Kuber"])
        expectEqual(store.entries.first?.observationCount, 1)
        expectEqual(store.entries.first?.status, .suggested)
        expect(store.activeTerms.isEmpty, "A one-off suggestion became active")
        store.observe(candidateTerms: ["kuber"])
        expectEqual(store.entries.first?.observationCount, 2)
        store.observe(candidateTerms: ["Kuber"])
        expectEqual(store.entries.first?.status, .active)
        expectEqual(store.activeTerms, ["Kuber"])
    }

    private static func testManualEntryPromotesSuggestion() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        store.observe(candidateTerms: ["Obsidian"])
        let entry = try! store.addManual("Obsidian")
        expectEqual(entry.source, .manual)
        expectEqual(entry.status, .active)
        expectEqual(store.entries.count, 1)
    }

    private static func testAutomaticLearningToggle() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }
        store.automaticLearningEnabled = false
        store.observe(candidateTerms: ["Cursor"])
        expect(store.entries.isEmpty, "Learning toggle was ignored")

        let reloaded = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expect(!reloaded.automaticLearningEnabled, "Learning toggle was not persisted")
    }

    private static func testLegacyMigrationRunsOnce() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("Megaphone\nSpeechAnalyzer, Kuber; Foundation Models", forKey: "legacy")
        let store = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expectEqual(Set(store.activeTerms), Set(["Megaphone", "SpeechAnalyzer", "Kuber", "Foundation Models"]))

        defaults.set("A later legacy edit", forKey: "legacy")
        let reloaded = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expectEqual(Set(reloaded.activeTerms), Set(["Megaphone", "SpeechAnalyzer", "Kuber", "Foundation Models"]))
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testPersistence() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        _ = try! store.addManual("Foundation Models")
        let reloaded = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        expectEqual(reloaded.activeTerms, ["Foundation Models"])
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testConservativeCandidateExtraction() {
        let candidates = DictionaryTermLearner.candidates(
            from: "Please send this to Kuber and keep SpeechAnalyzer, GPT-5, and JSON intact."
        )
        expect(candidates.contains("Kuber"), "Missed a mid-sentence name")
        expect(candidates.contains("SpeechAnalyzer"), "Missed an internal-cap technical term")
        expect(candidates.contains("GPT-5"), "Missed a versioned technical term")
        expect(candidates.contains("JSON"), "Missed an acronym")
        expect(!candidates.contains("Please"), "Learned sentence-initial capitalization")
        expect(!candidates.contains("send"), "Learned an ordinary word")
    }

    private static func testDismissedSuggestionStaysDismissed() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }
        store.observe(candidateTerms: ["Kuber"])
        let entry = store.entries[0]
        store.dismissSuggestion(id: entry.id)
        store.observe(candidateTerms: ["Kuber"])
        expectEqual(store.entries[0].status, .rejected)
        expectEqual(store.entries[0].observationCount, 1)
        let restored = try! store.addManual("Kuber")
        expectEqual(restored.status, .active)
        expectEqual(restored.source, .manual)
    }

    private static func testDecodesEntriesStoredBeforeRanking() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // A stored blob from before `starred`/`usageCount` existed.
        let legacyBlob = """
        [{"id":"1B8F4E2A-6C1D-4E5B-9A3F-2D7C8E0B4A61","term":"Megaphone","source":"manual",\
        "status":"active","isEnabled":true,"observationCount":0,"createdAt":776000000,"updatedAt":776000000}]
        """
        defaults.set(Data(legacyBlob.utf8), forKey: "entries")
        defaults.set(true, forKey: "migrated")
        let store = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expectEqual(store.entries.count, 1)
        expectEqual(store.entries.first?.term, "Megaphone")
        expectEqual(store.entries.first?.starred, false)
        expectEqual(store.entries.first?.usageCount, 0)
        expectEqual(store.activeTerms, ["Megaphone"])
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testPromptRankingOrder() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("Obsidian")
        _ = try! store.addManual("Kuber")
        let starredEntry = try! store.addManual("Zig")
        _ = try! store.addManual("Apple")
        store.setStarred(true, for: starredEntry.id)
        store.recordUsage(in: "Ship the Kuber build")
        store.recordUsage(in: "Ping Kuber about Obsidian")

        // Starred beats usage, usage beats alphabetical, alphabetical breaks ties.
        expectEqual(store.activeTerms, ["Zig", "Kuber", "Obsidian", "Apple"])
    }

    private static func testUsageMatchingRespectsWordBoundaries() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("AI")
        store.recordUsage(in: "We maintain the daily chain")
        expectEqual(store.entries.first?.usageCount, 0)
        store.recordUsage(in: "The AI pipeline, obviously.")
        expectEqual(store.entries.first?.usageCount, 1)
        // Punctuation is a boundary; repeats within one dictation count once.
        store.recordUsage(in: "ai, ai everywhere")
        expectEqual(store.entries.first?.usageCount, 2)
        expect(DictionaryStore.containsWholeWord("Foundation Models", in: "use Foundation Models."), "Missed a multi-word phrase")
        expect(!DictionaryStore.containsWholeWord("Foundation Models", in: "foundation modelscope"), "Matched inside a longer word")
    }

    private static func testUsageIncrementsOnlyEnabledEntries() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("SpeechAnalyzer")
        let disabled = try! store.addManual("Obsidian")
        store.setEnabled(false, for: disabled.id)
        store.observe(candidateTerms: ["Claurst"]) // suggested, not active
        store.recordUsage(in: "SpeechAnalyzer feeds Obsidian and Claurst")
        expectEqual(store.entries.first { $0.term == "SpeechAnalyzer" }?.usageCount, 1)
        expectEqual(store.entries.first { $0.term == "Obsidian" }?.usageCount, 0)
        expectEqual(store.entries.first { $0.term == "Claurst" }?.usageCount, 0)
    }

    private static func testStarAndUsagePersist() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        let entry = try! store.addManual("Megaphone")
        store.setStarred(true, for: entry.id)
        store.recordUsage(in: "Megaphone shipped")
        let reloaded = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        expectEqual(reloaded.entries.first?.starred, true)
        expectEqual(reloaded.entries.first?.usageCount, 1)
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testExportDocumentRoundTrip() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let starred = try! store.addManual("Megaphone")
        store.setStarred(true, for: starred.id)
        store.observe(candidateTerms: ["Kuber"])

        let document = store.exportDocument(exactCorrections: "mega phone → Megaphone")
        let decoded = try! DictionaryExportDocument.decode(try! document.encoded())

        expectEqual(decoded.megaphoneDictionaryVersion, DictionaryExportDocument.currentVersion)
        expectEqual(decoded.exactCorrections, "mega phone → Megaphone")
        // ISO-8601 drops sub-second precision, so compare everything but dates.
        expectEqual(decoded.entries.map(\.term), store.entries.map(\.term))
        expectEqual(decoded.entries.map(\.source), store.entries.map(\.source))
        expectEqual(decoded.entries.map(\.status), store.entries.map(\.status))
        expectEqual(decoded.entries.map(\.starred), store.entries.map(\.starred))
        expectEqual(decoded.entries.map(\.isEnabled), store.entries.map(\.isEnabled))
        expectEqual(decoded.entries.map(\.observationCount), store.entries.map(\.observationCount))
    }

    private static func testImportMergesByTerm() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("Megaphone")
        store.observe(candidateTerms: ["Kuber"]) // local suggestion
        store.observe(candidateTerms: ["Cursor"])
        store.dismissSuggestion(id: store.entries.first { $0.term == "Cursor" }!.id)
        store.observe(candidateTerms: ["Claurst"])
        store.dismissSuggestion(id: store.entries.first { $0.term == "Claurst" }!.id)

        let imported = [
            // Duplicate of a local active entry: stars and usage merge in.
            DictionaryEntry(term: "megaphone", source: .manual, status: .active, starred: true, usageCount: 9),
            // Explicitly taught on the other Mac: activates the local suggestion.
            DictionaryEntry(term: "Kuber", source: .manual, status: .active),
            // A mere suggestion elsewhere must not resurrect a local rejection.
            DictionaryEntry(term: "Cursor", source: .learned, status: .suggested),
            // But an explicit activation elsewhere wins over a local rejection.
            DictionaryEntry(term: "claurst", source: .manual, status: .active),
            // Brand new term.
            DictionaryEntry(term: "SpeechAnalyzer", source: .manual, status: .active),
            DictionaryEntry(term: "   ", source: .manual, status: .active)
        ]
        let result = store.importEntries(imported)

        expectEqual(result.addedCount, 1)
        expectEqual(result.updatedCount, 3)
        let megaphone = store.entries.first { $0.term == "Megaphone" }!
        expectEqual(megaphone.starred, true)
        expectEqual(megaphone.usageCount, 9)
        expectEqual(store.entries.first { $0.term == "Kuber" }?.status, .active)
        expectEqual(store.entries.first { $0.term == "Cursor" }?.status, .rejected)
        let claurst = store.entries.first { $0.term == "Claurst" }!
        expectEqual(claurst.status, .active)
        expectEqual(claurst.source, .manual)
        expect(claurst.isEnabled, "Reactivated entry should be enabled")
        expectEqual(store.entries.first { $0.term == "SpeechAnalyzer" }?.status, .active)
        expectEqual(store.entries.count, 5)
    }

    private static func testImportPersists() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        store.importEntries([
            DictionaryEntry(term: "Obsidian", source: .manual, status: .active, starred: true, usageCount: 4)
        ])
        let reloaded = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        expectEqual(reloaded.activeTerms, ["Obsidian"])
        expectEqual(reloaded.entries.first?.starred, true)
        expectEqual(reloaded.entries.first?.usageCount, 4)
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testMergedCorrections() {
        let merged = DictionaryStore.mergedCorrections(
            local: "mega phone → Megaphone\n",
            imported: "MEGA PHONE → Megaphone\nkuber → Kuber\n\nkuber → Kuber"
        )
        expectEqual(merged.text, "mega phone → Megaphone\nkuber → Kuber")
        expectEqual(merged.addedCount, 1)

        let fromEmpty = DictionaryStore.mergedCorrections(local: "", imported: "a → b")
        expectEqual(fromEmpty.text, "a → b")
        expectEqual(fromEmpty.addedCount, 1)

        let nothingNew = DictionaryStore.mergedCorrections(local: "a → b", imported: "a → b\n")
        expectEqual(nothingNew.text, "a → b")
        expectEqual(nothingNew.addedCount, 0)
    }

    private static func makeStore() -> (DictionaryStore, UserDefaults) {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated", legacyVocabularyKey: "legacy"),
            defaults
        )
    }

    private static func clear(_ defaults: UserDefaults) {
        guard let suite = defaults.volatileDomainNames.first(where: { $0.hasPrefix("DictionaryStoreTests.") }) else { return }
        defaults.removePersistentDomain(forName: suite)
    }

    private static func expectThrows(_ expected: DictionaryStoreError, operation: () throws -> Void) {
        do {
            try operation()
            fatalError("Expected \(expected)")
        } catch let error as DictionaryStoreError {
            expectEqual(error, expected)
        } catch {
            fatalError("Expected DictionaryStoreError, got \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) {
        if actual != expected { fatalError("Expected \(expected), got \(actual)") }
    }

    /// Auto-learning was storing the full stop that ended the sentence.
    private static func testLearnedTermsLoseSentencePunctuation() {
        expectEqual(DictionaryStore.cleaned("Friday."), "Friday")
        expectEqual(DictionaryStore.cleaned("Amsterdam,"), "Amsterdam")
        expectEqual(DictionaryStore.cleaned("really?!"), "really")
        expectEqual(DictionaryStore.cleaned("  Slack.  "), "Slack")
        // A dot that belongs to the term stays.
        expectEqual(DictionaryStore.cleaned("CLAUDE.md"), "CLAUDE.md")
        expectEqual(DictionaryStore.cleaned("e.g."), "e.g.")
        expectEqual(DictionaryStore.cleaned("n8n.io"), "n8n.io")
    }

    /// The half that makes a learned correction actionable. A term alone can
    /// only ever be a preferred spelling — advisory, and capped at 40 of them.
    /// The heard->written pair can become a deterministic rule that always
    /// fires. It was being discarded, which is why 161 already-learned entries
    /// cannot be promoted.
    private static func testLearningRecordsTheMishearThatCausedIt() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = store.observeEditCorrection(
            DictationEditCorrection(heard: "Merrick", written: "Marek", isCaseOnly: false)
        )
        expectEqual(store.entries.first { $0.term == "Marek" }?.observedSource, "Merrick")

        // A later, different mishearing of the same word must not overwrite the
        // first — that one is the observation the correction was learned from.
        _ = store.observeEditCorrection(
            DictationEditCorrection(heard: "Marrick", written: "Marek", isCaseOnly: false)
        )
        expectEqual(store.entries.first { $0.term == "Marek" }?.observedSource, "Merrick")
        expectEqual(store.entries.first { $0.term == "Marek" }?.observationCount, 2)
    }

}
