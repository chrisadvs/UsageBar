import XCTest
@testable import TokenUsageWidget

class MockUsageAPIClient: UsageAPIClientProtocol {
    func fetchUsage() async throws -> UsageSnapshot {
        return UsageSnapshot(groups: [])
    }
}

class AccountTests: XCTestCase {
    func testAccountFilteringAndLookup() {
        let client = MockUsageAPIClient()
        let creds = WKWebViewCredentialProvider()
        
        let claude = Account(id: "Claude", providerType: .claude, credentialProvider: creds, apiClient: client, isPaused: false, isVisibleInMainPanel: true)
        let gemini = Account(id: "Gemini", providerType: .gemini, credentialProvider: creds, apiClient: client, isPaused: false, isVisibleInMainPanel: false)
        let antigravity = Account(id: "Antigravity", providerType: .antigravity, credentialProvider: creds, apiClient: client, isPaused: true, isVisibleInMainPanel: true)
        
        let accounts = [claude, gemini, antigravity]
        
        // Lookup by selectedAccountID
        let found = accounts.first { $0.id == "Gemini" }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.providerType, .gemini)
        
        // Filter visible in main panel
        let visible = accounts.filter { $0.isVisibleInMainPanel }
        XCTAssertEqual(visible.count, 2)
        XCTAssertTrue(visible.contains { $0.id == "Claude" })
        XCTAssertTrue(visible.contains { $0.id == "Antigravity" })
        XCTAssertFalse(visible.contains { $0.id == "Gemini" })
        
        // Filter active (not paused) for fetching
        let active = accounts.filter { !$0.isPaused }
        XCTAssertEqual(active.count, 2)
        XCTAssertTrue(active.contains { $0.id == "Claude" })
        XCTAssertTrue(active.contains { $0.id == "Gemini" })
        XCTAssertFalse(active.contains { $0.id == "Antigravity" })
    }
}
