import XCTest
@testable import TokenUsageWidget

final class AppLoggerTests: XCTestCase {
    func testRingBufferLimitAndDroppingOldest() {
        let logger = AppLogger(maxEntries: 5)
        XCTAssertEqual(logger.entries.count, 0)
        
        for i in 1...5 {
            logger.log("Message \(i)")
        }
        XCTAssertEqual(logger.entries.count, 5)
        XCTAssertEqual(logger.entries.first?.message, "Message 1")
        XCTAssertEqual(logger.entries.last?.message, "Message 5")
        
        for i in 6...8 {
            logger.log("Message \(i)")
        }
        XCTAssertEqual(logger.entries.count, 5)
        XCTAssertEqual(logger.entries.first?.message, "Message 4")
        XCTAssertEqual(logger.entries.last?.message, "Message 8")
    }
    
    func testClearLogs() {
        let logger = AppLogger(maxEntries: 10)
        logger.log("Test message")
        XCTAssertEqual(logger.entries.count, 1)
        logger.clear()
        XCTAssertEqual(logger.entries.count, 0)
    }
    
    func testFormattedLogs() {
        let logger = AppLogger(maxEntries: 5)
        logger.log("Test 1", level: .info)
        logger.log("Test 2", level: .error)
        let formatted = logger.formattedLogs()
        XCTAssertTrue(formatted.contains("[INFO] Test 1"))
        XCTAssertTrue(formatted.contains("[ERROR] Test 2"))
    }
}
