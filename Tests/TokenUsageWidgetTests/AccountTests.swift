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
        let pausedThirdAccount = Account(id: "GeminiSecondary", providerType: .gemini, credentialProvider: creds, apiClient: client, isPaused: true, isVisibleInMainPanel: true)

        let accounts = [claude, gemini, pausedThirdAccount]

        // Lookup by selectedAccountID
        let found = accounts.first { $0.id == "Gemini" }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.providerType, .gemini)

        // Filter visible in main panel
        let visible = accounts.filter { $0.isVisibleInMainPanel }
        XCTAssertEqual(visible.count, 2)
        XCTAssertTrue(visible.contains { $0.id == "Claude" })
        XCTAssertTrue(visible.contains { $0.id == "GeminiSecondary" })
        XCTAssertFalse(visible.contains { $0.id == "Gemini" })

        // Filter active (not paused) for fetching
        let active = accounts.filter { !$0.isPaused }
        XCTAssertEqual(active.count, 2)
        XCTAssertTrue(active.contains { $0.id == "Claude" })
        XCTAssertTrue(active.contains { $0.id == "Gemini" })
        XCTAssertFalse(active.contains { $0.id == "GeminiSecondary" })
    }
    
    @MainActor
    func testSelectionFallbackWhenInvisibleOrPaused() {
        let viewModel = WidgetViewModel()
        XCTAssertEqual(viewModel.selectedAccountID, "Claude")

        // Selecting a paused account should be rejected, falling back to a valid one.
        if let idx = viewModel.accounts.firstIndex(where: { $0.id == "Gemini" }) {
            viewModel.accounts[idx].isPaused = true
        }
        viewModel.selectedAccountID = "Gemini"
        XCTAssertNotEqual(viewModel.selectedAccountID, "Gemini")
        XCTAssertEqual(viewModel.selectedAccountID, "Claude")

        // Unpause it again so it's eligible as a fallback target below.
        if let idx = viewModel.accounts.firstIndex(where: { $0.id == "Gemini" }) {
            viewModel.accounts[idx].isPaused = false
        }

        if let idx = viewModel.accounts.firstIndex(where: { $0.id == "Claude" }) {
            viewModel.accounts[idx].isVisibleInMainPanel = false
        }
        XCTAssertEqual(viewModel.selectedAccountID, "Gemini")
    }
    
    @MainActor
    func testAccountVisibilityPersistence() {
        UserDefaults.standard.removeObject(forKey: "visibleAccountIDs")
        
        var viewModel = WidgetViewModel()
        XCTAssertTrue(viewModel.accounts.allSatisfy { $0.isVisibleInMainPanel })
        
        if let idx = viewModel.accounts.firstIndex(where: { $0.id == "Gemini" }) {
            viewModel.accounts[idx].isVisibleInMainPanel = false
        }
        
        let savedIDs = UserDefaults.standard.array(forKey: "visibleAccountIDs") as? [String]
        XCTAssertNotNil(savedIDs)
        XCTAssertFalse(savedIDs?.contains("Gemini") ?? true)
        XCTAssertTrue(savedIDs?.contains("Claude") ?? false)
        
        viewModel = WidgetViewModel()
        let gemini = viewModel.accounts.first(where: { $0.id == "Gemini" })
        XCTAssertEqual(gemini?.isVisibleInMainPanel, false)
        
        // Clean up for subsequent tests
        UserDefaults.standard.removeObject(forKey: "visibleAccountIDs")
    }
}
