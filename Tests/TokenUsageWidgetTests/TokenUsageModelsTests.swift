import XCTest
@testable import TokenUsageWidget

final class TokenUsageModelsTests: XCTestCase {
    func testTokenCountsAddition() {
        let a = TokenCounts(input: 100, output: 50, cacheRead: 1000, cacheCreation5m: 200, cacheCreation1h: 50)
        let b = TokenCounts(input: 300, output: 150, cacheRead: 2000, cacheCreation5m: 100, cacheCreation1h: 25)
        
        let sum = a + b
        XCTAssertEqual(sum.input, 400)
        XCTAssertEqual(sum.output, 200)
        XCTAssertEqual(sum.cacheRead, 3000)
        XCTAssertEqual(sum.cacheCreation5m, 300)
        XCTAssertEqual(sum.cacheCreation1h, 75)
        XCTAssertEqual(sum.cacheCreationTotal, 375)
        XCTAssertEqual(sum.total, 400 + 200 + 3000 + 375)
        
        var mut = a
        mut += b
        XCTAssertEqual(mut, sum)
    }
    
    func testTokenFormatting() {
        XCTAssertEqual(TokenFormatter.formatCompact(500), "500")
        XCTAssertEqual(TokenFormatter.formatCompact(1500), "1.5K")
        XCTAssertEqual(TokenFormatter.formatCompact(12_400_000), "12.4M")
        XCTAssertEqual(TokenFormatter.formatCompact(2_480_000_000), "2.48B")
        
        XCTAssertEqual(TokenFormatter.formatUSD(nil), "—")
        XCTAssertEqual(TokenFormatter.formatUSD(0.0), "$0.00")
        XCTAssertEqual(TokenFormatter.formatUSD(3.214), "$3.21")
        XCTAssertEqual(TokenFormatter.formatUSD(0.005), "$0.005")
    }
    
    func testFiveHourWindowStartCalculation() {
        let formatter = ISO8601DateFormatter()
        let resetsAt = formatter.date(from: "2026-08-20T15:00:00Z")!
        
        // Window start = resetsAt - 5h
        let window = UsageWindow(
            kind: .fiveHour,
            percentRemaining: 50.0,
            severity: .green,
            resetsAtFormatted: "2h 30m",
            resetsAtAbsolute: "15:00",
            resetsAtDate: resetsAt
        )
        
        XCTAssertNotNil(window.resetsAtDate)
        let computedStart = window.resetsAtDate?.addingTimeInterval(-5 * 3600)
        let expectedStart = formatter.date(from: "2026-08-20T10:00:00Z")!
        XCTAssertEqual(computedStart, expectedStart)
        
        // Unstarted window with nil resetsAtDate must return nil
        let unstartedWindow = UsageWindow(
            kind: .fiveHour,
            percentRemaining: 100.0,
            severity: .green,
            resetsAtFormatted: "Starts when used",
            resetsAtAbsolute: nil,
            resetsAtDate: nil
        )
        XCTAssertNil(unstartedWindow.resetsAtDate)
        let unstartedStart = unstartedWindow.resetsAtDate?.addingTimeInterval(-5 * 3600)
        XCTAssertNil(unstartedStart)
    }
    
    func testTokenStatsSnapshotCodableRoundTrip() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let bucket = DailyModelBucket(
            day: day,
            model: "claude-sonnet-5",
            counts: TokenCounts(input: 10, output: 20, cacheRead: 30, cacheCreation5m: 5, cacheCreation1h: 0),
            messageCount: 1
        )
        let entry = FileIndexEntry(
            path: "/path/to/test.jsonl",
            byteSize: 1024,
            modifiedAt: Date(),
            scannedByteOffset: 1024,
            aggregated: [bucket]
        )
        let record = TokenUsageRecord(
            messageID: "msg_123",
            timestamp: Date(),
            model: "claude-sonnet-5",
            counts: TokenCounts(input: 10, output: 20, cacheRead: 30, cacheCreation5m: 5, cacheCreation1h: 0)
        )
        let pricing = PricingSnapshot(
            lastFetchedAt: Date(),
            prices: ["claude-sonnet-5": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 10.0)]
        )
        let snapshot = TokenStatsSnapshot(
            schemaVersion: 1,
            lastScanAt: Date(),
            fileIndex: [entry],
            recentRecords: [record],
            pricing: pricing
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TokenStatsSnapshot.self, from: data)
        
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.fileIndex.count, 1)
        XCTAssertEqual(decoded.fileIndex.first?.path, "/path/to/test.jsonl")
        XCTAssertEqual(decoded.recentRecords.count, 1)
        XCTAssertEqual(decoded.recentRecords.first?.messageID, "msg_123")
        XCTAssertEqual(decoded.pricing?.prices["claude-sonnet-5"]?.inputPerMillion, 2.0)
    }
    
    func testTrendBucketPropertiesAndCodable() throws {
        let date = Date(timeIntervalSince1970: 1724150400) // 2024-08-20 10:40:00 UTC
        let bucket = TrendBucket(
            bucketStart: date,
            model: "claude-sonnet-5",
            counts: TokenCounts(input: 100, output: 50, cacheRead: 20, cacheCreation5m: 10, cacheCreation1h: 5),
            messageCount: 3
        )
        
        XCTAssertEqual(bucket.id, "\(date.timeIntervalSince1970)_claude-sonnet-5")
        XCTAssertEqual(bucket.model, "claude-sonnet-5")
        XCTAssertEqual(bucket.counts.total, 185)
        XCTAssertEqual(bucket.messageCount, 3)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(bucket)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrendBucket.self, from: data)
        
        XCTAssertEqual(decoded, bucket)
        XCTAssertEqual(decoded.id, bucket.id)
    }
}
