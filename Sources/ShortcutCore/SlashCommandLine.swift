import Foundation

/// Drops the full stop the recogniser puts after a dictation that is nothing
/// but a slash command.
///
/// Measured 2026-08-05 from Bryce's own history — the period is already in the
/// RAW transcript, so this is the recogniser closing a sentence, the same source
/// as the excess commas. Nothing in Megaphone adds it:
///
///     spoken  "slash omp"
///     raw     "/omp."
///     shipped "/omp."   <- does not fire as a command
///
/// Deliberately narrow: the WHOLE utterance must be one slash-command token.
/// Over 9,804 real dictations, four came back as a lone slash command and none
/// of them kept a trailing period, and none at all were a slash command followed
/// by more words — so there is no evidence for the wider rule and it is not
/// written. A sentence that merely *contains* a path ("check /etc/hosts.") is
/// untouched, because it is not the entire utterance.
///
/// Only ever removes one trailing `.`. It cannot touch `?` or `!` — if the
/// speaker's command really did end a question, that mark is theirs.
enum SlashCommandLine {
    static func stripTerminalPeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.hasSuffix(".") else { return text }

        let command = String(trimmed.dropLast())
        // "/omp", "/code-review", "/ui-verify". No spaces: one token only.
        guard command.hasPrefix("/") else { return text }
        let body = command.dropFirst()
        guard let first = body.first, first.isLetter,
              body.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return text }

        // Rebuild in place so surrounding whitespace the caller chose is kept.
        guard let range = text.range(of: trimmed) else { return command }
        return text.replacingCharacters(in: range, with: command)
    }
}
