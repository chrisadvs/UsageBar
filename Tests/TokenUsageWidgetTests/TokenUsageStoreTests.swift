import XCTest
@testable import TokenUsageWidget

final class TokenUsageStoreTests: XCTestCase {
    var tempDirectory: URL!
    var storageFileURL: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("TokenUsageStoreTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        storageFileURL = tempDirectory.appendingPathComponent("token-stats.json")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    func testDeduplicationAndFiltering() async throws {
        // Prepare test transcripts directory
        let projectsDir = tempDirectory.appendingPathComponent("projects/test-project")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        
        let fixtureURL = Bundle.moduleURLOrFallback(fileName: "synthetic_transcript.jsonl")
        let fixtureData: Data
        if let url = fixtureURL, let data = try? Data(contentsOf: url) {
            fixtureData = data
        } else {
            // Fallback inline synthetic data
            let inline = """
            {"type":"assistant","timestamp":"2026-08-20T10:00:00.000Z","message":{"id":"msg_synthetic_01","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
            {"type":"assistant","timestamp":"2026-08-20T10:01:00.000Z","message":{"id":"msg_stream_01","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":150,"ephemeral_1h_input_tokens":50}}}}
            {"type":"assistant","timestamp":"2026-08-20T10:01:00.100Z","message":{"id":"msg_stream_01","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":150,"ephemeral_1h_input_tokens":50}}}}
            {"type":"assistant","timestamp":"2026-08-20T10:01:00.200Z","message":{"id":"msg_stream_01","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":150,"ephemeral_1h_input_tokens":50}}}}
            {"type":"assistant","timestamp":"2026-08-20T10:05:00.000Z","message":{"id":"msg_haiku_02","model":"claude-haiku-4-5-20251001","usage":{"input_tokens":500,"output_tokens":200,"cache_creation_input_tokens":300,"cache_read_input_tokens":4000}}}
            {"type":"user","timestamp":"2026-08-20T10:06:00.000Z","message":{"id":"msg_user_01"}}
            {"type":"assistant","timestamp":"2026-08-20T10:10:00.000Z","message":{"id":"msg_unknown_03","model":"claude-future-experimental","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
            """
            fixtureData = inline.data(using: .utf8)!
        }
        
        let testFile = projectsDir.appendingPathComponent("session1.jsonl")
        try fixtureData.write(to: testFile)
        
        let testPricing = PricingSnapshot(
            lastFetchedAt: Date(),
            prices: [
                "claude-sonnet-5": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 10.0),
                "claude-haiku-4-5": ModelPricing(inputPerMillion: 1.0, outputPerMillion: 5.0)
            ]
        )
        
        let store = TokenUsageStore(
            transcriptsDirectory: tempDirectory.appendingPathComponent("projects"),
            storageFileURL: storageFileURL,
            initialPricing: testPricing
        )
        
        let now = ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")!
        let windowStart = ISO8601DateFormatter().date(from: "2026-08-20T09:00:00Z")!
        
        let summaries = await store.refresh(fiveHourWindowStart: windowStart, now: now)
        
        let fiveHourSummary = summaries[.currentFiveHourWindow]
        XCTAssertNotNil(fiveHourSummary)
        
        // Assert deduplication: msg_stream_01 was repeated 3 times with 100 input, 50 output, etc.
        // It must only be counted ONCE.
        // Total expected across:
        // - msg_stream_01: input 100, output 50, cacheRead 1000, 5m 150, 1h 50
        // - msg_haiku_02: input 500, output 200, cacheRead 4000, 5m 300, 1h 0
        // - msg_unknown_03: input 1000, output 500, cacheRead 0, 5m 0, 1h 0
        // Total input = 100 + 500 + 1000 = 1600
        // Total output = 50 + 200 + 500 = 750
        // Total cacheRead = 1000 + 4000 = 5000
        // Total 5m = 150 + 300 = 450
        // Total 1h = 50
        XCTAssertEqual(fiveHourSummary?.counts.input, 1600)
        XCTAssertEqual(fiveHourSummary?.counts.output, 750)
        XCTAssertEqual(fiveHourSummary?.counts.cacheRead, 5000)
        XCTAssertEqual(fiveHourSummary?.counts.cacheCreation5m, 450)
        XCTAssertEqual(fiveHourSummary?.counts.cacheCreation1h, 50)
        
        // Assert <synthetic> is not in perModel
        XCTAssertNil(fiveHourSummary?.perModel["<synthetic>"])
        
        // Assert per-model counts
        XCTAssertEqual(fiveHourSummary?.perModel["claude-sonnet-5"]?.input, 100)
        XCTAssertEqual(fiveHourSummary?.perModel["claude-haiku-4-5-20251001"]?.input, 500)
        XCTAssertEqual(fiveHourSummary?.perModel["claude-future-experimental"]?.input, 1000)
        
        // Assert unknown model was tracked as unpriced
        XCTAssertEqual(fiveHourSummary?.unpricedMessageCount, 1)
    }
    
    func testIncrementalScanAppend() async throws {
        let projectsDir = tempDirectory.appendingPathComponent("projects/p1")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        
        let testFile = projectsDir.appendingPathComponent("test.jsonl")
        let initialLine = """
        {"type":"assistant","timestamp":"2026-08-20T10:00:00.000Z","message":{"id":"msg_init","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n
        """
        try initialLine.data(using: .utf8)!.write(to: testFile)
        
        let store = TokenUsageStore(
            transcriptsDirectory: tempDirectory.appendingPathComponent("projects"),
            storageFileURL: storageFileURL
        )
        
        let now = ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")!
        var summaries = await store.refresh(fiveHourWindowStart: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(summaries[.today]?.counts.input, 10)
        
        // Now append a second line
        let appendLine = """
        {"type":"assistant","timestamp":"2026-08-20T10:30:00.000Z","message":{"id":"msg_append","model":"claude-sonnet-5","usage":{"input_tokens":30,"output_tokens":40,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n
        """
        let fileHandle = try FileHandle(forWritingTo: testFile)
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: appendLine.data(using: .utf8)!)
        try fileHandle.close()
        
        // Rescan
        summaries = await store.refresh(fiveHourWindowStart: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(summaries[.today]?.counts.input, 40) // 10 + 30
        XCTAssertEqual(summaries[.today]?.counts.output, 60) // 20 + 40
    }
    
    func testSchemaVersionMismatchRecovery() async throws {
        // Write a snapshot file with incompatible schemaVersion 999
        let badSnapshotJSON = """
        {
          "schemaVersion": 999,
          "lastScanAt": "2026-08-20T10:00:00Z",
          "fileIndex": [],
          "recentRecords": []
        }
        """
        try badSnapshotJSON.data(using: .utf8)!.write(to: storageFileURL)
        
        let store = TokenUsageStore(
            transcriptsDirectory: tempDirectory.appendingPathComponent("projects"),
            storageFileURL: storageFileURL
        )
        
        let now = Date()
        let summaries = await store.refresh(fiveHourWindowStart: nil, now: now)
        
        // Must not crash and should rebuild empty summaries
        XCTAssertNotNil(summaries[.today])
        XCTAssertEqual(summaries[.today]?.counts.input, 0)
    }
    
    func testTrendBucketsFiveHourWindow30MinBucketing() async throws {
        let projectsDir = tempDirectory.appendingPathComponent("projects/trend-5h")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let testFile = projectsDir.appendingPathComponent("session.jsonl")
        
        let content = """
        {"type":"assistant","timestamp":"2026-08-20T08:30:00.000Z","message":{"id":"msg_early","model":"claude-sonnet-5","usage":{"input_tokens":500,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"2026-08-20T10:05:00.000Z","message":{"id":"msg_1","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"2026-08-20T10:25:00.000Z","message":{"id":"msg_2","model":"claude-sonnet-5","usage":{"input_tokens":50,"output_tokens":25,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"2026-08-20T10:35:00.000Z","message":{"id":"msg_3","model":"claude-sonnet-5","usage":{"input_tokens":200,"output_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"2026-08-20T10:45:00.000Z","message":{"id":"msg_4","model":"claude-haiku-4-5","usage":{"input_tokens":300,"output_tokens":150,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n
        """
        try content.data(using: .utf8)!.write(to: testFile)
        
        let store = TokenUsageStore(
            transcriptsDirectory: tempDirectory.appendingPathComponent("projects"),
            storageFileURL: storageFileURL
        )
        
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-08-20T12:00:00Z")!
        let windowStart = formatter.date(from: "2026-08-20T09:00:00Z")!
        
        _ = await store.refresh(fiveHourWindowStart: windowStart, now: now)
        
        // When windowStart is nil, returns empty list
        let nilWindowBuckets = await store.getTrendBuckets(scope: .currentFiveHourWindow, fiveHourWindowStart: nil, now: now)
        XCTAssertTrue(nilWindowBuckets.isEmpty)
        
        // When windowStart is valid
        let buckets = await store.getTrendBuckets(scope: .currentFiveHourWindow, fiveHourWindowStart: windowStart, now: now)
        
        // Expected buckets:
        // 1. 10:00:00 sonnet (100 + 50 = 150 input, 2 messages)
        // 2. 10:30:00 haiku (300 input, 1 message)
        // 3. 10:30:00 sonnet (200 input, 1 message)
        XCTAssertEqual(buckets.count, 3)
        
        let b0 = buckets[0]
        XCTAssertEqual(b0.model, "claude-sonnet-5")
        XCTAssertEqual(b0.counts.input, 150)
        XCTAssertEqual(b0.counts.output, 75)
        XCTAssertEqual(b0.messageCount, 2)
        
        let b1 = buckets[1]
        XCTAssertEqual(b1.model, "claude-haiku-4-5")
        XCTAssertEqual(b1.counts.input, 300)
        XCTAssertEqual(b1.messageCount, 1)
        
        let b2 = buckets[2]
        XCTAssertEqual(b2.model, "claude-sonnet-5")
        XCTAssertEqual(b2.counts.input, 200)
        XCTAssertEqual(b2.messageCount, 1)
    }
    
    func testTrendBucketsTodayHourlyBucketing() async throws {
        let projectsDir = tempDirectory.appendingPathComponent("projects/trend-today")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let testFile = projectsDir.appendingPathComponent("session.jsonl")
        
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        let midnightPlus15 = startOfToday.addingTimeInterval(15 * 60)
        let hour8_15 = startOfToday.addingTimeInterval(8 * 3600 + 15 * 60)
        let hour8_45 = startOfToday.addingTimeInterval(8 * 3600 + 45 * 60)
        let hour9_05 = startOfToday.addingTimeInterval(9 * 3600 + 5 * 60)
        let yesterday23_50 = startOfToday.addingTimeInterval(-10 * 60) // Yesterday 23:50
        
        let formatter = ISO8601DateFormatter()
        let content = """
        {"type":"assistant","timestamp":"\(formatter.string(from: yesterday23_50))","message":{"id":"msg_yest","model":"claude-sonnet-5","usage":{"input_tokens":1000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"\(formatter.string(from: midnightPlus15))","message":{"id":"msg_mid","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"\(formatter.string(from: hour8_15))","message":{"id":"msg_h8_1","model":"claude-sonnet-5","usage":{"input_tokens":200,"output_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"\(formatter.string(from: hour8_45))","message":{"id":"msg_h8_2","model":"claude-sonnet-5","usage":{"input_tokens":300,"output_tokens":30,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","timestamp":"\(formatter.string(from: hour9_05))","message":{"id":"msg_h9","model":"claude-haiku-4-5","usage":{"input_tokens":400,"output_tokens":40,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n
        """
        try content.data(using: .utf8)!.write(to: testFile)
        
        let store = TokenUsageStore(
            transcriptsDirectory: tempDirectory.appendingPathComponent("projects"),
            storageFileURL: storageFileURL
        )
        
        _ = await store.refresh(fiveHourWindowStart: nil, now: now)
        
        let todayBuckets = await store.getTrendBuckets(scope: .today, fiveHourWindowStart: nil, now: now)
        
        // Expected 3 hourly buckets:
        // 1. 00:00 sonnet (100 input, 1 message)
        // 2. 08:00 sonnet (200 + 300 = 500 input, 2 messages)
        // 3. 09:00 haiku (400 input, 1 message)
        XCTAssertEqual(todayBuckets.count, 3)
        
        XCTAssertEqual(todayBuckets[0].counts.input, 100)
        XCTAssertEqual(todayBuckets[0].messageCount, 1)
        
        XCTAssertEqual(todayBuckets[1].counts.input, 500)
        XCTAssertEqual(todayBuckets[1].messageCount, 2)
        
        XCTAssertEqual(todayBuckets[2].counts.input, 400)
        XCTAssertEqual(todayBuckets[2].messageCount, 1)
    }
    
    func testTrendBucketsThisWeekAndThisMonthAndAllTrends() async throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        
        var aggregated: [DailyModelBucket] = []
        // Add buckets for past 15 days
        for dayOffset in 0..<15 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: now)!
            aggregated.append(DailyModelBucket(
                day: day,
                model: "claude-sonnet-5",
                counts: TokenCounts(input: 100, output: 50, cacheRead: 0, cacheCreation5m: 0, cacheCreation1h: 0),
                messageCount: 1
            ))
        }
        
        let entry = FileIndexEntry(
            path: "/path/to/test.jsonl",
            byteSize: 1000,
            modifiedAt: now,
            scannedByteOffset: 1000,
            aggregated: aggregated
        )
        
        let snapshot = TokenStatsSnapshot(
            schemaVersion: 1,
            lastScanAt: now,
            fileIndex: [entry],
            recentRecords: [],
            pricing: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        try data.write(to: storageFileURL)
        
        let store = TokenUsageStore(
            transcriptsDirectory: tempDirectory.appendingPathComponent("projects"),
            storageFileURL: storageFileURL
        )
        
        // .thisWeek is aligned to the calendar week (Calendar.weekOfYear), matching
        // computeSummaries' .thisWeek scope — not a rolling 7-day window — so the expected
        // count depends on how many days into the current calendar week "now" falls on.
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let expectedWeekDays = calendar.dateComponents([.day], from: startOfWeek, to: now).day! + 1

        let weekBuckets = await store.getTrendBuckets(scope: .thisWeek, fiveHourWindowStart: nil, now: now)
        XCTAssertEqual(weekBuckets.count, expectedWeekDays)

        let monthBuckets = await store.getTrendBuckets(scope: .thisMonth, fiveHourWindowStart: nil, now: now)
        XCTAssertEqual(monthBuckets.count, 15) // We only created 15 days of data, all within the rolling 30-day window

        let allTrends = await store.getAllTrendBuckets(fiveHourWindowStart: nil, now: now)
        XCTAssertEqual(allTrends.keys.count, 4)
        XCTAssertEqual(allTrends[.thisWeek]?.count, expectedWeekDays)
        XCTAssertEqual(allTrends[.thisMonth]?.count, 15)
        XCTAssertEqual(allTrends[.currentFiveHourWindow]?.count, 0)
    }
}

fileprivate extension Bundle {
    static func moduleURLOrFallback(fileName: String) -> URL? {
        let currentFileURL = URL(fileURLWithPath: #file)
        let fixturesDir = currentFileURL.deletingLastPathComponent().appendingPathComponent("Fixtures")
        let fixtureFile = fixturesDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fixtureFile.path) {
            return fixtureFile
        }
        return nil
    }
}
