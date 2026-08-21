import XCTest
@testable import TokenUsageWidget

final class GeminiWebUsageParserTests: XCTestCase {
    func testParsingValidJSON() throws {
        let batchexecuteResponse = """
)]}'
1234
[["wrb.fr","jSf9Qc","[2, [[1, 0.25, 1, [[1785000000, 1]]], [2, 0.40, 2, [[1786000000, 1]]]], false]",null,null,null,"generic"]]
"""
        // Mock current time: 1784991600
        let now = Date(timeIntervalSince1970: 1784991600)
        
        let snapshot = try GeminiWebUsageParser.parse(string: batchexecuteResponse, now: now)
        
        XCTAssertEqual(snapshot.groups.count, 1)
        
        let group = snapshot.groups[0]
        XCTAssertEqual(group.windows.count, 2)
        
        let win5h = group.windows[0]
        XCTAssertEqual(win5h.kind, .fiveHour)
        XCTAssertEqual(win5h.percentRemaining, 75.0, accuracy: 0.0001)
        XCTAssertEqual(win5h.severity, .green)
        XCTAssertEqual(win5h.resetsAtFormatted, "2h 20m")
        
        let winWeekly = group.windows[1]
        XCTAssertEqual(winWeekly.kind, .weekly)
        XCTAssertEqual(winWeekly.percentRemaining, 60.0, accuracy: 0.0001)
        XCTAssertEqual(winWeekly.severity, .green)
        XCTAssertEqual(winWeekly.resetsAtFormatted, "11d 16h")
    }
}
