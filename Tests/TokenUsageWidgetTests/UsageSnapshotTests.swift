import XCTest
@testable import TokenUsageWidget

final class UsageSnapshotTests: XCTestCase {
    
    func testParsingValidJSON() throws {
        let jsonString = """
        {
          "five_hour": { "utilization": 43.0, "resets_at": "2026-07-24T05:00:00.000000+00:00" },
          "seven_day": { "utilization": 5.0, "resets_at": "2026-07-26T00:00:00.000000+00:00" }
        }
        """
        
        let jsonData = jsonString.data(using: .utf8)!
        
        // Mock current time: 2026-07-24T00:00:00Z
        let now = ISO8601DateFormatter().date(from: "2026-07-24T00:00:00Z")!
        
        let snapshot = try UsageParser.parse(json: jsonData, now: now)
        
        // Five hour checks
        XCTAssertEqual(snapshot.fiveHour.percentRemaining, 57.0) // 100 - 43
        XCTAssertEqual(snapshot.fiveHour.severity, .green) // 43 < 50
        XCTAssertEqual(snapshot.fiveHour.resetsAtFormatted, "5h 0m")
        
        // Seven day checks
        XCTAssertEqual(snapshot.sevenDay.percentRemaining, 95.0) // 100 - 5
        XCTAssertEqual(snapshot.sevenDay.severity, .green) // 5 < 50
        XCTAssertEqual(snapshot.sevenDay.resetsAtFormatted, "2d 0h")
    }
    
    func testSeverityThresholds() throws {
        let thresholds: [(Double, Severity)] = [
            (49.0, .green),
            (50.0, .yellow),
            (70.0, .yellow),
            (89.0, .yellow),
            (90.0, .red),
            (91.0, .red)
        ]
        
        let now = ISO8601DateFormatter().date(from: "2026-07-24T00:00:00Z")!
        
        for (utilization, expectedSeverity) in thresholds {
            let jsonString = """
            {
              "five_hour": { "utilization": \(utilization), "resets_at": "2026-07-24T05:00:00Z" },
              "seven_day": { "utilization": \(utilization), "resets_at": "2026-07-24T05:00:00Z" }
            }
            """
            
            let snapshot = try UsageParser.parse(json: jsonString.data(using: .utf8)!, now: now)
            XCTAssertEqual(snapshot.fiveHour.severity, expectedSeverity, "Utilization \(utilization) should be \(expectedSeverity)")
        }
    }
}
