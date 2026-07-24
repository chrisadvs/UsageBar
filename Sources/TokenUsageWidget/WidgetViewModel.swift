import SwiftUI
import Foundation

@MainActor
class WidgetViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var errorMsg: String?
    @Published var isLoading = false
    
    // Debug properties for manual cookie input
    @Published var cookieInput: String = ""
    @Published var showDebugInput = false
    
    private let apiClient: UsageAPIClient
    private let credentialProvider: CredentialProvider
    
    init() {
        let provider = KeychainCredentialProvider()
        self.credentialProvider = provider
        // Currently hardcoding the orgId as per the Ticket 03 spec (use known fixed value)
        self.apiClient = UsageAPIClient(credentialProvider: provider, orgId: "0e15182b-a6f3-496b-aebb-23ec37dbe6be")
    }
    
    func loadData() {
        guard !isLoading else { return }
        isLoading = true
        errorMsg = nil
        
        Task {
            do {
                let newSnapshot = try await apiClient.fetchUsage()
                self.snapshot = newSnapshot
            } catch {
                self.errorMsg = error.localizedDescription
                self.snapshot = nil
            }
            self.isLoading = false
        }
    }
    
    func saveCookie() {
        credentialProvider.saveCookie(cookieInput.trimmingCharacters(in: .whitespacesAndNewlines))
        cookieInput = ""
        showDebugInput = false
        loadData()
    }
}
