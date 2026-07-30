import Foundation

/// The migration is the part that can silently change behaviour, so most of
/// these cover it: every context must come out of the upgrade doing exactly what
/// the old global switches did there.
enum DictationProfileTests {
    static func run() {
        standardCoversEveryContext()
        migrationPreservesAllOnBehaviour()
        migrationPreservesAllOffBehaviour()
        migrationHonoursTheContextSpecificFlags()
        migrationKeepsPerContextFormality()
        migrationFallsBackToStandardFormality()
        roundTripsThroughJSON()
        decodingToleratesAMissingSwitch()
        unknownContextFallsBackToStandard()
    }

    private static let allOn = DictationProfileSet.LegacySwitches(
        lightCommasInCasualChat: true, questionMarks: true, questionMarksInCode: true,
        listsInCode: true, listsInCasualChat: true, restarts: true,
        lowercaseContinuations: true, learnEdits: true
    )
    private static let allOff = DictationProfileSet.LegacySwitches(
        lightCommasInCasualChat: false, questionMarks: false, questionMarksInCode: false,
        listsInCode: false, listsInCasualChat: false, restarts: false,
        lowercaseContinuations: false, learnEdits: false
    )

    static func standardCoversEveryContext() {
        let set = DictationProfileSet.standard
        expect(set.byContext.count == AppWritingContext.allContexts.count, "standard covers all six")
        // The two contexts that ship non-balanced.
        expect(set.profile(for: .casualChat).formality == .casual, "casual chat ships casual")
        expect(set.profile(for: .email).formality == .formal, "email ships formal")
        expect(set.profile(for: .casualChat).lightCommas, "light commas ship on in casual chat")
        expect(!set.profile(for: .document).lightCommas, "light commas ship off elsewhere")
    }

    static func migrationPreservesAllOnBehaviour() {
        let set = DictationProfileSet.migrating(legacy: allOn, formalityByContext: [:])
        for context in AppWritingContext.allContexts {
            let p = set.profile(for: context)
            expect(p.questionMarks, "\(context.rawValue): question marks stay on")
            expect(p.lists, "\(context.rawValue): lists stay on")
            expect(p.restarts, "\(context.rawValue): restarts stay on")
            expect(p.lowercaseContinuations, "\(context.rawValue): continuations stay on")
            expect(p.learnEdits, "\(context.rawValue): learn-from-edits stays on")
        }
        expect(set.profile(for: .casualChat).lightCommas, "light commas migrate into casual chat")
        expect(!set.profile(for: .workChat).lightCommas, "light commas do not leak elsewhere")
    }

    static func migrationPreservesAllOffBehaviour() {
        let set = DictationProfileSet.migrating(legacy: allOff, formalityByContext: [:])
        for context in AppWritingContext.allContexts {
            let p = set.profile(for: context)
            expect(!p.questionMarks, "\(context.rawValue): question marks stay off")
            expect(!p.restarts, "\(context.rawValue): restarts stay off")
            expect(!p.lowercaseContinuations, "\(context.rawValue): continuations stay off")
            expect(!p.learnEdits, "\(context.rawValue): learn-from-edits stays off")
            expect(!p.lightCommas, "\(context.rawValue): light commas stay off")
        }
        // Lists had no global master switch — only the two context opt-ins — so
        // everywhere else keeps its always-on behaviour.
        expect(!set.profile(for: .codeOrTerminal).lists, "code lists follow lists_in_code")
        expect(!set.profile(for: .casualChat).lists, "chat lists follow lists_in_casual_chat")
        expect(set.profile(for: .document).lists, "documents kept lists on regardless")
        expect(set.profile(for: .neutral).lists, "general writing kept lists on regardless")
    }

    static func migrationHonoursTheContextSpecificFlags() {
        // Question marks on globally but off in code: only that context loses them.
        var legacy = allOn
        legacy.questionMarksInCode = false
        let set = DictationProfileSet.migrating(legacy: legacy, formalityByContext: [:])
        expect(!set.profile(for: .codeOrTerminal).questionMarks, "code loses question marks")
        expect(set.profile(for: .email).questionMarks, "email keeps them")

        // Off globally but the code sub-switch on: still off, the master wins.
        var legacy2 = allOff
        legacy2.questionMarksInCode = true
        let set2 = DictationProfileSet.migrating(legacy: legacy2, formalityByContext: [:])
        expect(!set2.profile(for: .codeOrTerminal).questionMarks, "master switch wins over the sub-switch")

        // The two list opt-ins are independent.
        var legacy3 = allOff
        legacy3.listsInCode = true
        let set3 = DictationProfileSet.migrating(legacy: legacy3, formalityByContext: [:])
        expect(set3.profile(for: .codeOrTerminal).lists, "code lists on")
        expect(!set3.profile(for: .casualChat).lists, "chat lists still off")
    }

    static func migrationKeepsPerContextFormality() {
        let set = DictationProfileSet.migrating(
            legacy: allOn,
            formalityByContext: ["casualChat": "casual", "email": "formal", "workChat": "balanced"]
        )
        expect(set.profile(for: .casualChat).formality == .casual, "casual carried over")
        expect(set.profile(for: .email).formality == .formal, "formal carried over")
        expect(set.profile(for: .workChat).formality == .balanced, "balanced carried over")
    }

    static func migrationFallsBackToStandardFormality() {
        // A context absent from the old dictionary, and an unparseable value,
        // both fall back to what that context ships with.
        let set = DictationProfileSet.migrating(
            legacy: allOn, formalityByContext: ["email": "nonsense"]
        )
        expect(set.profile(for: .email).formality == .formal, "bad value falls back to email's default")
        expect(set.profile(for: .casualChat).formality == .casual, "missing falls back to chat's default")
        expect(set.profile(for: .document).formality == .balanced, "missing falls back to balanced")
    }

    static func roundTripsThroughJSON() {
        var set = DictationProfileSet.standard
        var p = set.profile(for: .document)
        p.lists = false
        p.formality = .formal
        set.set(p, for: .document)

        guard let data = try? JSONEncoder().encode(set),
              let decoded = try? JSONDecoder().decode(DictationProfileSet.self, from: data) else {
            fatalError("DictationProfile: JSON round trip failed")
        }
        expect(decoded == set, "round trip is lossless")
        expect(!decoded.profile(for: .document).lists, "the edited switch survived")
        expect(decoded.profile(for: .document).formality == .formal, "the edited formality survived")
    }

    static func decodingToleratesAMissingSwitch() {
        // A profile saved by a build that predates `lowercaseContinuations`.
        let json = """
        {"byContext":{"email":{"formality":"formal","lightCommas":false,"questionMarks":true,
        "lists":true,"restarts":true,"learnEdits":true}}}
        """
        guard let decoded = try? JSONDecoder().decode(
            DictationProfileSet.self, from: Data(json.utf8)
        ) else {
            fatalError("DictationProfile: decoding a profile missing a switch should not fail")
        }
        let p = decoded.profile(for: .email)
        expect(p.formality == .formal, "saved values survive")
        expect(p.lowercaseContinuations, "the new switch falls back to its default rather than false")
    }

    static func unknownContextFallsBackToStandard() {
        let empty = DictationProfileSet()
        expect(empty.profile(for: .email).formality == .formal, "empty set still answers with the default")
        expect(empty.profile(for: .casualChat).lightCommas, "and with the right per-context default")
    }

    // MARK: helpers

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError("DictationProfile: \(message)")
        }
    }
}
