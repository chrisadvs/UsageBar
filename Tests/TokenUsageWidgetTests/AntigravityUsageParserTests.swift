import XCTest
@testable import TokenUsageWidget

final class AntigravityUsageParserTests: XCTestCase {
    func testParsingValidJSON() throws {
        let jsonString = """
        {
          "groups": [
            {
              "buckets": [
                {
                  "bucketId": "gemini-weekly",
                  "displayName": "Weekly Limit",
                  "window": "weekly",
                  "resetTime": "2026-07-28T18:59:38Z",
                  "description": "You have used some of your weekly limit, it will fully refresh in 4 days.",
                  "remainingFraction": 0.68236494
                },
                {
                  "bucketId": "gemini-5h",
                  "displayName": "Five Hour Limit",
                  "window": "5h",
                  "resetTime": "2026-07-24T21:01:53Z",
                  "description": "You have used some of your 5-hour limit, it will fully refresh in 2 hours, 14 minutes.",
                  "remainingFraction": 0.9749946
                }
              ],
              "displayName": "Gemini Models",
              "description": "Models within this group: Gemini Flash, Gemini Pro"
            },
            {
              "buckets": [
                {
                  "bucketId": "3p-weekly",
                  "displayName": "Weekly Limit",
                  "window": "weekly",
                  "resetTime": "2026-07-29T18:32:28Z",
                  "description": "You have used some of your weekly limit, it will fully refresh in 4 days, 23 hours.",
                  "remainingFraction": 0.93752295
                },
                {
                  "bucketId": "3p-5h",
                  "displayName": "Five Hour Limit",
                  "window": "5h",
                  "resetTime": "2026-07-24T23:47:48Z",
                  "remainingFraction": 1
                }
              ],
              "displayName": "Claude and GPT models",
              "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS"
            }
          ],
          "description": "Within each group, models share a weekly limit and a 5-hour limit."
        }
        """
        
        let jsonData = jsonString.data(using: .utf8)!
        
        // Mock current time: 2026-07-24T18:00:00Z
        let now = ISO8601DateFormatter().date(from: "2026-07-24T18:00:00Z")!
        
        let snapshot = try AntigravityUsageParser.parse(json: jsonData, now: now)
        
        XCTAssertEqual(snapshot.groups.count, 2)
        
        let group1 = snapshot.groups[0]
        XCTAssertEqual(group1.name, "Gemini Models")
        XCTAssertEqual(group1.windows.count, 2)
        
        let g1_5h = group1.windows[0]
        XCTAssertEqual(g1_5h.kind, .fiveHour)
        XCTAssertEqual(g1_5h.percentRemaining, 97.49946, accuracy: 0.00001)
        XCTAssertEqual(g1_5h.severity, .green)
        XCTAssertEqual(g1_5h.resetsAtFormatted, "3h 1m") // diff between 21:01 and 18:00
        
        let g1_weekly = group1.windows[1]
        XCTAssertEqual(g1_weekly.kind, .weekly)
        XCTAssertEqual(g1_weekly.percentRemaining, 68.236494, accuracy: 0.00001)
        XCTAssertEqual(g1_weekly.severity, .green)
        XCTAssertEqual(g1_weekly.resetsAtFormatted, "4d 0h") // diff between 28T18:59 and 24T18:00 is ~97 hours = 4d 1h
        
        let group2 = snapshot.groups[1]
        XCTAssertEqual(group2.name, "Claude and GPT models")
        XCTAssertEqual(group2.windows.count, 2)
        
        let g2_5h = group2.windows[0]
        XCTAssertEqual(g2_5h.kind, .fiveHour)
        XCTAssertEqual(g2_5h.percentRemaining, 100.0, accuracy: 0.00001)
        XCTAssertEqual(g2_5h.severity, .green)
        XCTAssertEqual(g2_5h.resetsAtFormatted, "5h 47m")
        
        let g2_weekly = group2.windows[1]
        XCTAssertEqual(g2_weekly.kind, .weekly)
        XCTAssertEqual(g2_weekly.percentRemaining, 93.752295, accuracy: 0.00001)
        XCTAssertEqual(g2_weekly.severity, .green)
        XCTAssertEqual(g2_weekly.resetsAtFormatted, "5d 0h") // diff between 29T18:32 and 24T18:00 is 5d 0h
    }
}
