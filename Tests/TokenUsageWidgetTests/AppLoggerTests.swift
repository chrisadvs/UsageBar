import XCTest
import SwiftUI
import AppKit
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
    
    func testLogViewLayoutWithVeryLongTextDoesNotExceedMaxWidth() {
        let logger = AppLogger.shared
        logger.clear()
        
        // Insert a very long log line (e.g. over 1000 characters without spaces or newlines)
        let longString = String(repeating: "A_VERY_LONG_LOG_MESSAGE_THAT_SHOULD_WRAP_AND_NOT_PUSH_THE_WINDOW_OFFSCREEN_", count: 15)
        logger.log(longString, level: .error)
        
        let logView = LogView()
        let hostingView = NSHostingView(rootView: logView)
        
        // Ask the hosting view for its fitting size when given a large unbound proposal
        let fittingSize = hostingView.fittingSize
        
        // Assert that the width of the view does not exceed 480 (allowing a tiny delta for borders/padding if any, e.g. <= 490)
        XCTAssertLessThanOrEqual(fittingSize.width, 490, "LogView width should be constrained by maxWidth: 480 even when containing extremely long log lines.")
        XCTAssertGreaterThanOrEqual(fittingSize.width, 350, "LogView should maintain its minWidth of 350.")
    }
    
    @MainActor
    func testConfigurationWindowControllerWorkflow() {
        let viewModel = WidgetViewModel()
        let controller = ConfigurationWindowController.shared
        
        // 1. Show window
        controller.showWindow(viewModel: viewModel)
        let win = controller.value(forKey: "window") as? NSWindow
        XCTAssertNotNil(win, "Configuration window should be created.")
        XCTAssertTrue(win?.isVisible == true, "Configuration window should be visible.")
        
        // 2. Simulate refresh while open
        viewModel.loadData()
        
        // 3. Close window
        controller.closeWindow()
    }
}
