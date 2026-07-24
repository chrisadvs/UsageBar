import SwiftUI
import Foundation
import UserNotifications

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
    
    private var previousSnapshot: UsageSnapshot?
    
    init() {
        let provider = WKWebViewCredentialProvider()
        self.credentialProvider = provider
        // Currently hardcoding the orgId as per the Ticket 03 spec (use known fixed value)
        self.apiClient = UsageAPIClient(credentialProvider: provider, orgId: "0e15182b-a6f3-496b-aebb-23ec37dbe6be")
        
        requestNotificationPermission()
        startPolling()
        
        LoginWindowController.shared.onLoginSuccess = { [weak self] in
            self?.loadData()
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func startPolling() {
        loadData() // Initial background load
        
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000) // 5 minutes
                self.loadData()
            }
        }
    }
    
    func loadData() {
        guard !isLoading else { return }
        isLoading = true
        errorMsg = nil
        
        Task {
            do {
                let newSnapshot = try await apiClient.fetchUsage()
                self.checkAndNotifyIfNeeded(old: self.previousSnapshot, new: newSnapshot)
                self.previousSnapshot = newSnapshot
                self.snapshot = newSnapshot
            } catch let error as APIError {
                if error == .missingCookie || error == .unauthorized {
                    self.errorMsg = "Please log in to Claude."
                    LoginWindowController.shared.showLogin()
                } else {
                    self.errorMsg = error.localizedDescription
                }
                self.snapshot = nil
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
    
    private func checkAndNotifyIfNeeded(old: UsageSnapshot?, new: UsageSnapshot) {
        let fiveHourWasRed = old?.fiveHour.severity == .red
        let fiveHourIsRed = new.fiveHour.severity == .red
        
        if !fiveHourWasRed && fiveHourIsRed {
            let percentStr = String(format: "%.1f", 100 - new.fiveHour.percentRemaining)
            sendNotification(title: "Claude Usage Alert", body: "5-Hour window is running low (" + percentStr + "% used).")
        }
        
        let sevenDayWasRed = old?.sevenDay.severity == .red
        let sevenDayIsRed = new.sevenDay.severity == .red
        
        if !sevenDayWasRed && sevenDayIsRed {
            let percentStr = String(format: "%.1f", 100 - new.sevenDay.percentRemaining)
            sendNotification(title: "Claude Usage Alert", body: "7-Day window is running low (" + percentStr + "% used).")
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
