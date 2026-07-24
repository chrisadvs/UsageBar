import SwiftUI
import Foundation
import UserNotifications

@MainActor
class WidgetViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var errorMsg: String?
    @Published var isLoading = false
    
    // Provider Selection
    @Published var selectedProvider: String {
        didSet {
            UserDefaults.standard.set(selectedProvider, forKey: "selectedProvider")
            loadData()
        }
    }
    
    // Debug properties for manual credential input
    @Published var credentialInput: String = ""
    @Published var showDebugInput = false
    
    private let claudeApiClient: UsageAPIClient
    private let antigravityApiClient: AntigravityUsageAPIClient
    
    private let claudeCredentialProvider: CredentialProvider
    private let antigravityCredentialProvider: CredentialProvider
    
    private var previousSnapshot: UsageSnapshot?
    
    init() {
        self.selectedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? "Claude"
        
        self.claudeCredentialProvider = WKWebViewCredentialProvider()
        self.antigravityCredentialProvider = AntigravityCredentialProvider()
        
        self.claudeApiClient = UsageAPIClient(credentialProvider: claudeCredentialProvider, orgId: "0e15182b-a6f3-496b-aebb-23ec37dbe6be")
        self.antigravityApiClient = AntigravityUsageAPIClient(credentialProvider: antigravityCredentialProvider)
        
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
                let newSnapshot: UsageSnapshot
                if selectedProvider == "Claude" {
                    newSnapshot = try await claudeApiClient.fetchUsage()
                } else {
                    newSnapshot = try await antigravityApiClient.fetchUsage()
                }
                
                self.checkAndNotifyIfNeeded(old: self.previousSnapshot, new: newSnapshot)
                self.previousSnapshot = newSnapshot
                self.snapshot = newSnapshot
            } catch let error as APIError {
                if error == .missingCookie || error == .unauthorized {
                    self.errorMsg = "Please log in to \(selectedProvider)."
                    if selectedProvider == "Claude" {
                        LoginWindowController.shared.showLogin()
                    }
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
    
    func saveCredential() {
        let provider = selectedProvider == "Claude" ? claudeCredentialProvider : antigravityCredentialProvider
        provider.saveCredential(credentialInput.trimmingCharacters(in: .whitespacesAndNewlines))
        credentialInput = ""
        showDebugInput = false
        loadData()
    }
    
    func providerIcon() -> NSImage {
        let path = selectedProvider == "Claude" ? "/Applications/Claude.app" : "/Applications/Antigravity IDE.app"
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    private func checkAndNotifyIfNeeded(old: UsageSnapshot?, new: UsageSnapshot) {
        let oldGroups = old?.groups ?? []
        let newGroups = new.groups
        
        for newGroup in newGroups {
            let oldGroup = oldGroups.first(where: { $0.name == newGroup.name })
            
            for newWin in newGroup.windows {
                if newWin.severity == .red {
                    let oldWin = oldGroup?.windows.first(where: { $0.kind == newWin.kind })
                    let wasRed = oldWin?.severity == .red
                    
                    if !wasRed {
                        let percentStr = String(format: "%.1f", 100 - newWin.percentRemaining)
                        let windowName = newWin.kind == .fiveHour ? "5-Hour" : "Weekly"
                        let title = "Usage Alert"
                        
                        let groupName = newGroup.name ?? ""
                        let groupContext = groupName.isEmpty ? "" : "\(groupName) "
                        let body = "\(selectedProvider) — \(groupContext)\(windowName) window is running low (" + percentStr + "% used)."
                        
                        sendNotification(title: title, body: body)
                    }
                }
            }
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
