import Foundation

enum TransformStoreTests {
    static func run() {
        testBuiltInsAreAvailableByDefault()
        testInvocationMatchingPositives()
        testInvocationMatchingNegatives()
        testMultiWordUserTransformMatching()
        testStoreRoundTripMergesBuiltIns()
        testDecodedTransformsNeverClaimBuiltInStatus()
        testUserTransformShadowsBuiltInName()
        testMissingKeyReadsAsMissing()
        testReadableJSONReadsAsValue()
        testEmptyStoredListIsNotMistakenForCorruption()
        testWrongTypedJSONIsQuarantinedNotLost()
        testUndecodableDataIsQuarantinedNotLost()
        testWrongTypedStringIsQuarantinedNotLost()
        testQuarantineNeverOverwritesTheFirstBackup()
        testQuarantineSurvivesTheOverwriteThatUsedToLoseData()
    }

    private static func testBuiltInsAreAvailableByDefault() {
        let resolved = TransformStore.resolved(userTransforms: [])
        expect(resolved.count == 2, "Expected exactly the two built-ins, got \(resolved.count)")
        expect(resolved.contains { $0.name == "Polish" && $0.isBuiltIn }, "Polish built-in missing")
        expect(resolved.contains { $0.name == "Prompt" && $0.isBuiltIn }, "Prompt built-in missing")
        expect(
            resolved.allSatisfy { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            "Built-in transforms must carry a visible instruction"
        )
    }

    private static func testInvocationMatchingPositives() {
        let transforms = TransformStore.resolved(userTransforms: [])
        let polishInvocations = [
            "polish",
            "Polish",
            "POLISH THAT",
            "polish this",
            "polish that.",
            "Polish that!",
            "apply polish",
            "Apply Polish."
        ]
        for command in polishInvocations {
            expect(
                TransformStore.match(command: command, in: transforms)?.name == "Polish",
                "Expected \(command.debugDescription) to invoke Polish"
            )
        }
        expect(
            TransformStore.match(command: "prompt that.", in: transforms)?.name == "Prompt",
            "Expected \"prompt that.\" to invoke Prompt"
        )
        expect(
            TransformStore.match(command: "apply prompt", in: transforms)?.name == "Prompt",
            "Expected \"apply prompt\" to invoke Prompt"
        )
    }

    private static func testInvocationMatchingNegatives() {
        let transforms = TransformStore.resolved(userTransforms: [])
        let rejected = [
            "",
            "   ",
            "polish that thing up",
            "please polish that",
            "can you polish that",
            "polish that now",
            "polish it",
            "apply",
            "that",
            "this",
            "apply that",
            "shine that",
            "prompt engineering that",
            "make that a bulleted list"
        ]
        for command in rejected {
            expect(
                TransformStore.match(command: command, in: transforms) == nil,
                "\(command.debugDescription) must not invoke a transform"
            )
        }
    }

    private static func testMultiWordUserTransformMatching() {
        let meetingNotes = Transform(name: "Meeting Notes", instruction: "Turn the text into meeting notes.")
        let transforms = TransformStore.resolved(userTransforms: [meetingNotes])
        for command in ["meeting notes", "Meeting Notes that.", "apply meeting notes", "meeting-notes this"] {
            expect(
                TransformStore.match(command: command, in: transforms)?.id == meetingNotes.id,
                "Expected \(command.debugDescription) to invoke Meeting Notes"
            )
        }
        expect(
            TransformStore.match(command: "meeting", in: transforms) == nil,
            "A name prefix must not invoke a multi-word transform"
        )
        expect(
            TransformStore.match(command: "meeting notes for today that", in: transforms) == nil,
            "Extra words inside the invocation must fall through"
        )
    }

    private static func testStoreRoundTripMergesBuiltIns() {
        let custom = Transform(name: "Formalize", instruction: "Make the text formal.")
        let data = try! JSONEncoder().encode([custom])
        let decoded = try! JSONDecoder().decode([Transform].self, from: data)
        expect(decoded == [custom], "User transform did not survive an encode/decode round trip")

        let resolved = TransformStore.resolved(userTransforms: decoded)
        expect(resolved.count == 3, "Expected built-ins plus the decoded transform, got \(resolved.count)")
        expect(resolved.prefix(2).allSatisfy(\.isBuiltIn), "Built-ins should stay listed first")
        expect(resolved.last == custom, "Decoded user transform missing from the resolved list")
    }

    private static func testDecodedTransformsNeverClaimBuiltInStatus() {
        let data = try! JSONEncoder().encode(TransformStore.builtIns)
        let decoded = try! JSONDecoder().decode([Transform].self, from: data)
        expect(
            decoded.allSatisfy { !$0.isBuiltIn },
            "isBuiltIn must not be persisted; storage only ever holds user transforms"
        )
    }

    private static func testUserTransformShadowsBuiltInName() {
        let customPolish = Transform(name: "polish", instruction: "Polish, but in pirate speak.")
        let resolved = TransformStore.resolved(userTransforms: [customPolish])

        expect(resolved.count == 2, "Shadowed built-in must not be listed twice")
        expect(
            resolved.filter { TransformStore.normalize($0.name) == "polish" } == [customPolish],
            "User transform must replace the built-in with the same name"
        )
        let matched = TransformStore.match(command: "polish that", in: resolved)
        expect(matched?.id == customPolish.id, "Invocation must resolve to the user's shadowing transform")
        expect(
            matched?.instruction == "Polish, but in pirate speak.",
            "Shadowing transform must carry the user's instruction"
        )
        expect(
            TransformStore.match(command: "prompt that", in: resolved)?.isBuiltIn == true,
            "Unshadowed built-in must keep working"
        )
    }

    // MARK: - PreferenceLoad
    //
    // The shape under test is the one that cost 322 dictionary entries on
    // 2026-08-07: a value written under the wrong type makes `data(forKey:)`
    // return nil, the loader reports "nothing saved yet", and the next save
    // writes over the original. These check that an unreadable value is still
    // on disk after that save.

    private static func testMissingKeyReadsAsMissing() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        let loaded = PreferenceLoad.json([Transform].self, forKey: "user_transforms", from: defaults)
        guard case .missing = loaded else {
            expect(false, "An absent key must read as .missing, not .unreadable")
            return
        }
        expect(
            defaults.object(forKey: PreferenceLoad.quarantineKey(for: "user_transforms")) == nil,
            "A fresh install must not leave a backup key behind"
        )
    }

    private static func testReadableJSONReadsAsValue() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        let authored = [
            Transform(name: "Meeting Notes", instruction: "Turn the text into meeting notes."),
            Transform(name: "Formalize", instruction: "Make the text formal.")
        ]
        defaults.set(try! JSONEncoder().encode(authored), forKey: "user_transforms")

        let loaded = PreferenceLoad.json([Transform].self, forKey: "user_transforms", from: defaults)
        expect(loaded.value == authored, "A readable list must come back unchanged")
        expect(
            defaults.object(forKey: PreferenceLoad.quarantineKey(for: "user_transforms")) == nil,
            "A readable value must never be quarantined"
        )
    }

    private static func testEmptyStoredListIsNotMistakenForCorruption() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        defaults.set(try! JSONEncoder().encode([Transform]()), forKey: "user_transforms")

        let loaded = PreferenceLoad.json([Transform].self, forKey: "user_transforms", from: defaults)
        expect(loaded.value == [], "A deliberately emptied list is readable and must stay .value")
        expect(
            defaults.object(forKey: PreferenceLoad.quarantineKey(for: "user_transforms")) == nil,
            "Emptying the list on purpose must not create a backup on every launch"
        )
    }

    private static func testWrongTypedJSONIsQuarantinedNotLost() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        // What actually happened: the payload was there, under a type the
        // loader does not read. `data(forKey:)` returns nil for this.
        defaults.set(["Meeting Notes", "Formalize"], forKey: "user_transforms")
        expect(defaults.data(forKey: "user_transforms") == nil, "Precondition: the old guard sees nothing here")

        let loaded = PreferenceLoad.json([Transform].self, forKey: "user_transforms", from: defaults)
        guard case .unreadable = loaded else {
            expect(false, "A wrong-typed value must read as .unreadable, never as .missing")
            return
        }
        let recovered = defaults.array(forKey: PreferenceLoad.quarantineKey(for: "user_transforms")) as? [String]
        expect(recovered == ["Meeting Notes", "Formalize"], "The unreadable value must be recoverable verbatim")
    }

    private static func testUndecodableDataIsQuarantinedNotLost() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        // The other half of the same guard: right type, wrong contents. The
        // old `try?` swallowed this into the same empty result.
        let garbage = Data("{ not json".utf8)
        defaults.set(garbage, forKey: "voice_macros")

        let loaded = PreferenceLoad.json([Transform].self, forKey: "voice_macros", from: defaults)
        guard case .unreadable = loaded else {
            expect(false, "Undecodable data must read as .unreadable, never as .missing")
            return
        }
        expect(
            defaults.data(forKey: PreferenceLoad.quarantineKey(for: "voice_macros")) == garbage,
            "Undecodable bytes must be recoverable verbatim"
        )
    }

    private static func testWrongTypedStringIsQuarantinedNotLost() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        // `word_corrections` is hand-authored in a TextEditor, so an empty
        // read is one keystroke away from being saved back over the rules.
        defaults.set(["mega phone -> Megaphone"], forKey: "word_corrections")
        expect(defaults.string(forKey: "word_corrections") == nil, "Precondition: the old read sees nothing here")

        let loaded = PreferenceLoad.string(forKey: "word_corrections", from: defaults)
        guard case .unreadable = loaded else {
            expect(false, "A wrong-typed string must read as .unreadable, never as .missing")
            return
        }
        expect(loaded.value == nil, ".unreadable must not offer a value")
        let recovered = defaults.array(forKey: PreferenceLoad.quarantineKey(for: "word_corrections")) as? [String]
        expect(recovered == ["mega phone -> Megaphone"], "The unreadable rules must be recoverable verbatim")
    }

    private static func testQuarantineNeverOverwritesTheFirstBackup() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        let backupKey = PreferenceLoad.quarantineKey(for: "user_transforms")
        defaults.set(["the user's real work"], forKey: "user_transforms")
        _ = PreferenceLoad.json([Transform].self, forKey: "user_transforms", from: defaults)

        // A second corruption, after the app has already started fresh. The
        // backup holding the original must win.
        defaults.set(["whatever arrived later"], forKey: "user_transforms")
        _ = PreferenceLoad.json([Transform].self, forKey: "user_transforms", from: defaults)

        let recovered = defaults.array(forKey: backupKey) as? [String]
        expect(recovered == ["the user's real work"], "The first backup must survive a later corruption")
    }

    private static func testQuarantineSurvivesTheOverwriteThatUsedToLoseData() {
        let (defaults, suite) = makeDefaults()
        defer { wipe(defaults, suite) }

        defaults.set(["Meeting Notes", "Formalize"], forKey: "user_transforms")
        let loaded = PreferenceLoad.json([Transform].self, forKey: "user_transforms", from: defaults)

        // Exactly what AppState does next: the list came back empty, the user
        // adds one transform, and the `didSet` saves the whole array.
        let afterTheUserAddsOne = (loaded.value ?? []) + [
            Transform(name: "Bullets", instruction: "Turn the text into bullets.")
        ]
        defaults.set(try! JSONEncoder().encode(afterTheUserAddsOne), forKey: "user_transforms")

        let recovered = defaults.array(forKey: PreferenceLoad.quarantineKey(for: "user_transforms")) as? [String]
        expect(
            recovered == ["Meeting Notes", "Formalize"],
            "The original must still be on disk after the save that used to destroy it"
        )
    }

    // MARK: helpers

    /// An isolated suite per test. Never `.standard`: this runner would
    /// otherwise write into whichever bundle identity it inherits.
    private static func makeDefaults() -> (UserDefaults, String) {
        let suite = "megaphone.tests.preferenceload.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private static func wipe(_ defaults: UserDefaults, _ suite: String) {
        defaults.removePersistentDomain(forName: suite)
    }

    private static func expect(
        _ condition: Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
