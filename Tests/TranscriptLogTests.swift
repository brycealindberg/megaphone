import Foundation

/// The corpus log exists so a future correction rule can be judged against
/// thousands of real dictations instead of the 20 `PipelineHistory` keeps.
/// Everything here guards a property that would make it useless as evidence.
enum TranscriptLogTests {
    static func run() {
        testRecordsBothAgreementsAndDisagreements()
        testSkipsEmptyTranscripts()
        testSurvivesTranscriptsContainingNewlines()
        testTrimKeepsTheNewestRecords()
        testToleratesATruncatedFinalLine()
        testTrimActuallyBoundsBytesNotCount()
        testTrimDiscardsAPartialTailRatherThanKeepingIt()
        testARecordLargerThanTheBudgetIsRejected()
        testRecordSurvivesACallerThatDropsTheLogger()
    }

    /// The bound is bytes. Halving the record COUNT does not bound bytes when
    /// sizes vary by an order of magnitude, which real dictations do.
    private static func testTrimActuallyBoundsBytesNotCount() {
        withTemporaryLog(maxBytes: 2_000) { log, url in
            // One big record, then many small ones.
            log.writeForTesting(entry(String(repeating: "x", count: 1_200), "big"))
            for i in 0..<60 { log.writeForTesting(entry("s\(i)", "o\(i)")) }
            let size = (try? Data(contentsOf: url))?.count ?? 0
            expect(size <= 2_000, "file is \(size) bytes, over the 2000 budget")
            expect(!lines(url).isEmpty, "trim emptied the log")
            expect(lines(url).last?.raw == "s59", "newest record was dropped")
        }
    }

    /// A crash mid-append leaves a partial record. Trimming must drop it, not
    /// retain it — retaining it can replace a valid corpus with a fragment.
    private static func testTrimDiscardsAPartialTailRatherThanKeepingIt() {
        withTemporaryLog(maxBytes: 400) { log, url in
            for i in 0..<6 { log.writeForTesting(entry("raw \(i)", "out \(i)")) }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(#"{"t":"2026-08"#.utf8))
                try? handle.close()
            }
            // Force a trim with one more write.
            log.writeForTesting(entry("raw 6", "out 6"))
            let data = (try? Data(contentsOf: url)) ?? Data()
            expect(data.last == 0x0A, "file does not end on a record boundary")
            let written = lines(url)
            expect(!written.isEmpty, "trim emptied the log")
            // Every retained byte must still parse — no fragment survived.
            let recordCount = data.filter { $0 == 0x0A }.count
            expect(written.count == recordCount, "\(recordCount - written.count) unparseable line(s) retained")
        }
    }

    private static func testARecordLargerThanTheBudgetIsRejected() {
        withTemporaryLog(maxBytes: 200) { log, url in
            log.writeForTesting(entry("ok", "ok"))
            let before = (try? Data(contentsOf: url))?.count ?? 0
            log.writeForTesting(entry(String(repeating: "y", count: 5_000), "huge"))
            let after = (try? Data(contentsOf: url))?.count ?? 0
            expect(after == before, "an over-budget record was stored (\(before) -> \(after))")
            expect(lines(url).count == 1, "the existing corpus was disturbed")
        }
    }

    /// `record` must not silently drop writes for an instance the caller does
    /// not retain — a weak capture turns fire-and-forget into maybe-forget.
    private static func testRecordSurvivesACallerThatDropsTheLogger() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("megaphone-log-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("transcripts.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let done = DispatchSemaphore(value: 0)
        let drain = DispatchQueue(label: "drain")
        do {
            let log = TranscriptLog(fileURL: url, target: drain)
            log.record(raw: "kept", final: "kept", bundleIdentifier: nil, mode: "basic")
        }   // logger released here, before the queued write can have run
        drain.async { done.signal() }   // serial: runs after the write
        expect(done.wait(timeout: .now() + 5) == .success, "write never ran")
        expect(lines(url).first?.raw == "kept", "the record was dropped when the logger was released")
    }

    private static func withTemporaryLog(
        maxBytes: Int = 8 * 1024 * 1024,
        _ body: (TranscriptLog, URL) -> Void
    ) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("megaphone-log-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("transcripts.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        body(TranscriptLog(fileURL: url, maxBytes: maxBytes), url)
    }

    private static func lines(_ url: URL) -> [TranscriptLog.Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A, omittingEmptySubsequences: true).compactMap {
            try? JSONDecoder().decode(TranscriptLog.Entry.self, from: Data($0))
        }
    }

    private static func entry(_ raw: String, _ out: String) -> TranscriptLog.Entry {
        TranscriptLog.Entry(t: "2026-08-08T00:00:00Z", raw: raw, out: out, app: "com.test", mode: "basic")
    }

    /// The gate every correction rule must pass is "zero counterexamples", and
    /// a counterexample is a dictation the recogniser got RIGHT. A log holding
    /// only mistakes would make every candidate look perfect.
    private static func testRecordsBothAgreementsAndDisagreements() {
        withTemporaryLog { log, url in
            log.writeForTesting(entry("make an HTMO artifact", "make an HTML artifact"))
            log.writeForTesting(entry("make an HTML artifact", "make an HTML artifact"))
            let written = lines(url)
            expect(written.count == 2, "expected both rows, got \(written.count)")
            expect(written.contains { $0.raw == $0.out }, "the agreement row was dropped")
        }
    }

    /// `record` is asynchronous, so this drains the queue before asserting.
    /// Without the drain the assertion would pass before the write could even
    /// have happened — true for the wrong reason, and it would keep passing if
    /// the emptiness guard were deleted.
    private static func testSkipsEmptyTranscripts() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("megaphone-log-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("transcripts.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let drain = DispatchQueue(label: "drain-empty")
        let log = TranscriptLog(fileURL: url, target: drain)

        log.record(raw: "   \n ", final: "", bundleIdentifier: nil, mode: "basic")
        log.record(raw: "", final: "", bundleIdentifier: nil, mode: "basic")
        drain.sync {}
        expect(!FileManager.default.fileExists(atPath: url.path), "empty transcript was logged")

        // And the same path DOES write when the transcript is non-empty, so the
        // assertion above is about emptiness and not about the queue never running.
        log.record(raw: "real", final: "real", bundleIdentifier: nil, mode: "basic")
        drain.sync {}
        expect(lines(url).count == 1, "a non-empty transcript was not logged")
    }

    /// A dictation can contain newlines. JSON escapes them, so one record stays
    /// one line — if that ever stopped being true the whole file would misparse.
    private static func testSurvivesTranscriptsContainingNewlines() {
        withTemporaryLog { log, url in
            log.writeForTesting(entry("first\nsecond\nthird", "first\nsecond\nthird"))
            let data = (try? Data(contentsOf: url)) ?? Data()
            expect(data.filter { $0 == 0x0A }.count == 1, "a multi-line transcript broke the record separator")
            expect(lines(url).first?.raw == "first\nsecond\nthird", "newlines were not round-tripped")
        }
    }

    private static func testTrimKeepsTheNewestRecords() {
        withTemporaryLog(maxBytes: 900) { log, url in
            for i in 0..<40 { log.writeForTesting(entry("raw \(i)", "out \(i)")) }
            let written = lines(url)
            expect(!written.isEmpty, "trim emptied the log")
            expect(written.count < 40, "log was never trimmed (\(written.count) rows)")
            // Newest survive: the last write must always still be there.
            expect(written.last?.raw == "raw 39", "trim dropped the newest row, not the oldest")
        }
    }

    /// A write interrupted by a crash leaves a partial tail. That must cost one
    /// row, not the corpus.
    private static func testToleratesATruncatedFinalLine() {
        withTemporaryLog { log, url in
            log.writeForTesting(entry("complete", "complete"))
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(#"{"t":"2026"#.utf8))
                try? handle.close()
            }
            let written = lines(url)
            expect(written.count == 1, "a truncated tail cost more than itself (\(written.count) rows)")
            expect(written.first?.raw == "complete", "the intact row was lost")
        }
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
