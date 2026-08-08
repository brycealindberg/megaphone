import Foundation

/// Append-only record of what the recogniser heard and what was shipped.
///
/// This exists because `PipelineHistory` cannot be the corpus. It is capped at
/// 20 entries — about four hours — and every one of them carries the system
/// prompt (2.3 KB), the ranked vocabulary (1.4 KB) and a 160 KB WAV, while
/// `loadAllHistory()` fetches the lot into a `@Published` array on every edit.
/// Raising that cap to corpus size would reload megabytes on the main thread
/// for a feature nothing displays. Measured 2026-08-08:
///
///     transcripts  84 bytes/dictation      <- all the corpus needs
///     the rest    ~7 KB + 160 KB audio     <- what retention would really cost
///
/// So the corpus is its own file, holding only the four fields a correction
/// rule has to be judged against, and the history keeps its 20-entry cap.
///
/// **Agreements are recorded, not just disagreements.** The gate every rule in
/// `word_corrections` had to pass is "fires >= 2 times with ZERO
/// counterexamples", and a counterexample is a dictation where the recogniser
/// was RIGHT. A log of only the mistakes would make every candidate rule look
/// perfect — the same inversion that made `observationCount` useless as a gate.
///
/// Nothing in the app reads this back. It is written for offline analysis, so
/// a failure here must never surface: every path is `try?` and every write is
/// off the caller's thread.
///
/// Two known limitations, deliberate, so an analysis does not over-trust a row:
///
///   * **`out` is what the pipeline produced, not proof of delivery.** The row
///     is written when the transcript is finalised, which is before the
///     deferred paste runs. A paste that fails afterwards leaves a row saying
///     the text shipped. Rows with an empty result are filtered at the call
///     site, so the scratch, error and abandoned paths never appear — but a
///     failed paste of a non-empty result still does.
///   * **`mode` is read at finalisation.** Changing the cleanup mode in
///     Settings while a dictation is in flight can label the row with the mode
///     that is now selected rather than the one that produced it. Rare, and not
///     worth threading a captured mode through the delivery path for; treat a
///     lone mode-inconsistent row as noise rather than evidence.
final class TranscriptLog {
    struct Entry: Codable {
        let t: String
        let raw: String
        let out: String
        let app: String?
        let mode: String
    }

    static let shared = TranscriptLog()

    private let fileURL: URL
    private let maxBytes: Int
    /// Trim drops the oldest half rather than one line, so the rewrite cost is
    /// amortised across thousands of appends instead of paid on every one.
    private let queue: DispatchQueue
    private let formatter: ISO8601DateFormatter

    /// - Parameter target: where the private serial queue runs. The queue is
    ///   always created here and never injected: every file mutation has to be
    ///   serialised, and a caller handing in a `.concurrent` queue would let two
    ///   appends interleave, or let an atomic trim swap the inode under a handle
    ///   that is mid-append. Targeting keeps the QoS injectable without giving
    ///   away that guarantee.
    init(
        fileURL: URL? = nil,
        maxBytes: Int = 8 * 1024 * 1024,
        target: DispatchQueue? = nil
    ) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.maxBytes = max(maxBytes, 1)
        self.queue = DispatchQueue(
            label: "com.megaphone.transcriptlog",
            qos: .utility,
            target: target
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.formatter = formatter
    }

    static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Megaphone", isDirectory: true)
            .appendingPathComponent("transcripts.jsonl", isDirectory: false)
    }

    /// - Parameters:
    ///   - raw: the recogniser's transcript, before any pass touches it. This is
    ///     the side a mishear lives on, so it is the one that matters.
    ///   - final: what was actually inserted.
    ///   - mode: `basic`, `smart` or `exact` — a rule validated in one is not
    ///     automatically valid in another, because Basic never runs the model.
    /// Enqueues and returns. Deliberately does NO work on the caller's thread —
    /// not the whitespace scan, not the timestamp formatting, not the encode.
    /// This is called on the main actor immediately before the clipboard write
    /// and paste, so anything synchronous here is latency the user feels, and
    /// `ISO8601DateFormatter` is not free.
    ///
    /// `self` is captured strongly. The closure is short-lived and released the
    /// moment it runs, so there is no cycle — and a weak capture would silently
    /// drop records for any instance the caller does not otherwise retain,
    /// which turns a fire-and-forget write into a maybe-write.
    func record(
        raw: String,
        final: String,
        bundleIdentifier: String?,
        mode: String,
        at date: Date = Date()
    ) {
        queue.async {
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.write(Entry(
                t: self.formatter.string(from: date),
                raw: raw,
                out: final,
                app: bundleIdentifier,
                mode: mode
            ))
        }
    }

    /// Synchronous append. Tests call this; the app goes through `record`.
    func writeForTesting(_ entry: Entry) {
        write(entry)
    }

    var url: URL { fileURL }

    // MARK: Writing

    private func write(_ entry: Entry) {
        guard var line = try? JSONEncoder().encode(entry) else { return }
        // One object per line. A transcript can contain newlines, but
        // JSONEncoder escapes them, so the record separator stays unambiguous.
        line.append(0x0A)
        // A single record larger than the whole budget can never be stored
        // within it, and keeping it would leave the file permanently over the
        // bound no matter how much else is dropped.
        guard line.count <= maxBytes else { return }

        let manager = FileManager.default
        try? manager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var total: Int
        if manager.fileExists(atPath: fileURL.path) {
            repairPartialTail()
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            var appended = false
            do {
                let end = try handle.seekToEnd()
                try handle.write(contentsOf: line)
                appended = true
                total = Int(end) + line.count
            } catch {
                total = 0
            }
            try? handle.close()
            // Only consider trimming once the append actually landed. Trimming
            // on a failed write would evict real records to make room for one
            // that was never stored.
            guard appended else { return }
        } else {
            guard (try? line.write(to: fileURL, options: .atomic)) != nil else { return }
            total = line.count
        }

        if total > maxBytes { trimToBudget() }
    }

    /// Discard an incomplete record at the end of the file before appending.
    ///
    /// A write interrupted by a crash or a full disk leaves a partial record
    /// with no trailing newline. Appending after it does NOT leave one bad line
    /// — it concatenates the fragment and the new record into a single
    /// unparseable line, so one interruption costs the next good record too,
    /// and keeps costing one for as long as nothing repairs the tail.
    ///
    /// Checked on every append because that is the only moment it matters, but
    /// the cost is a seek and one byte; the whole-file read happens only when a
    /// fragment is actually there.
    private func repairPartialTail() {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        var needsRepair = false
        do {
            let end = try handle.seekToEnd()
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                needsRepair = try handle.read(upToCount: 1) != Data([0x0A])
            }
        } catch {
            needsRepair = false
        }
        try? handle.close()
        guard needsRepair else { return }

        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            // Nothing complete in the file at all.
            try? Data().write(to: fileURL, options: .atomic)
            return
        }
        try? data.prefix(through: lastNewline).write(to: fileURL, options: .atomic)
    }

    /// Drop whole records, oldest first, until the file fits the budget.
    ///
    /// Not "keep the newest half": record sizes vary by more than an order of
    /// magnitude (a two-word command against a 500-word brief), so halving the
    /// COUNT does not bound the BYTES, and the file could stay over budget
    /// indefinitely.
    private func trimToBudget() {
        guard var data = try? Data(contentsOf: fileURL) else { return }
        // A write interrupted by a crash leaves a partial record at the end.
        // Discard it before splitting — otherwise it is treated as a line and
        // can be the one thing retained, replacing a valid corpus with an
        // unparseable fragment.
        if data.last != 0x0A {
            guard let lastNewline = data.lastIndex(of: 0x0A) else { return }
            data = data.prefix(through: lastNewline)
        }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard lines.count > 1 else { return }

        var kept: [Data.SubSequence] = []
        var bytes = 0
        // Walk newest-first so the records that survive are the recent ones.
        for line in lines.reversed() {
            let cost = line.count + 1
            if bytes + cost > maxBytes { break }
            bytes += cost
            kept.append(line)
        }
        guard !kept.isEmpty else { return }

        var out = Data()
        out.reserveCapacity(bytes)
        for line in kept.reversed() {
            out.append(contentsOf: line)
            out.append(0x0A)
        }
        try? out.write(to: fileURL, options: .atomic)
    }
}
