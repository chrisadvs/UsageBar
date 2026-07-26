import SwiftUI
import Foundation
import UserNotifications
import ServiceManagement

@MainActor
class WidgetViewModel: ObservableObject {
    @Published var accounts: [Account] = [] {
        didSet {
            saveVisibility()
            updateCurrentSelectionState()
        }
    }
    @Published var selectedAccountID: String {
        didSet {
            UserDefaults.standard.set(selectedAccountID, forKey: "selectedProvider")
            updateCurrentSelectionState()
        }
    }
    
    // Alias for UI binding compatibility before Ticket 19
    var selectedProvider: String {
        get { selectedAccountID }
        set { selectedAccountID = newValue }
    }
    
    @Published var snapshot: UsageSnapshot?
    @Published var errorMsg: String?
    @Published var isLoading = false
    
    // Debug properties for manual credential input
    @Published var credentialInput: String = ""
    @Published var showDebugInput = false
    
    init() {
        let storedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? "Claude"
        self.selectedAccountID = storedProvider == "Antigravity" ? "Claude" : storedProvider
        
        let claudeCreds = WKWebViewCredentialProvider()
        let antigravityCreds = AntigravityCredentialProvider.shared
        let geminiCreds = GeminiWebCredentialProvider()
        
        let claudeClient = UsageAPIClient(credentialProvider: claudeCreds, orgId: "0e15182b-a6f3-496b-aebb-23ec37dbe6be")
        let antigravityClient = AntigravityUsageAPIClient(credentialProvider: antigravityCreds)
        let geminiClient = GeminiWebUsageAPIClient(credentialProvider: geminiCreds)
        
        let savedVisibleIDs = UserDefaults.standard.array(forKey: "visibleAccountIDs") as? [String]
        
        self.accounts = [
            Account(id: "Claude", providerType: .claude, credentialProvider: claudeCreds, apiClient: claudeClient, isPaused: false, isVisibleInMainPanel: savedVisibleIDs?.contains("Claude") ?? true),
            Account(id: "Gemini", providerType: .gemini, credentialProvider: geminiCreds, apiClient: geminiClient, isPaused: false, isVisibleInMainPanel: savedVisibleIDs?.contains("Gemini") ?? true),
            Account(id: "Antigravity", providerType: .antigravity, credentialProvider: antigravityCreds, apiClient: antigravityClient, isPaused: true, isVisibleInMainPanel: savedVisibleIDs?.contains("Antigravity") ?? true)
        ]
        
        updateCurrentSelectionState()
        requestNotificationPermission()
        startPolling()
        
        LoginWindowController.shared.onLoginSuccess = { [weak self] in
            self?.loadData()
        }
        
        AntigravityOAuthController.shared.onLoginSuccess = { [weak self] in
            self?.loadData()
        }
        
        GeminiLoginWindowController.shared.onLoginSuccess = { [weak self] in
            self?.loadData()
        }
    }
    
    private func saveVisibility() {
        guard !accounts.isEmpty else { return }
        let visibleIDs = accounts.filter { $0.isVisibleInMainPanel }.map { $0.id }
        UserDefaults.standard.set(visibleIDs, forKey: "visibleAccountIDs")
    }
    
    private func updateCurrentSelectionState() {
        if let current = accounts.first(where: { $0.id == selectedAccountID }),
           (!current.isVisibleInMainPanel || current.isPaused) {
            if let fallback = accounts.first(where: { $0.isVisibleInMainPanel && !$0.isPaused }) {
                self.selectedAccountID = fallback.id
                return
            }
        }
        if let account = accounts.first(where: { $0.id == selectedAccountID }) {
            self.snapshot = account.latestSnapshot
            self.errorMsg = account.errorMsg
        } else {
            self.snapshot = nil
            self.errorMsg = nil
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
        
        Task {
            let requestAccountID = self.selectedAccountID
            let currentAccounts = self.accounts
            AppLogger.shared.log("Initiating usage data refresh for \(currentAccounts.filter { !$0.isPaused }.count) active accounts...", level: .info)
            
            for account in currentAccounts {
                guard !account.isPaused else { continue }
                AppLogger.shared.log("Fetching usage for [\(account.id)]...", level: .info)
                
                do {
                    let newSnapshot = try await account.apiClient.fetchUsage()
                    AppLogger.shared.log("Successfully fetched usage for [\(account.id)]", level: .info)
                    
                    if let idx = self.accounts.firstIndex(where: { $0.id == account.id }) {
                        self.checkAndNotifyIfNeeded(account: self.accounts[idx], old: self.accounts[idx].latestSnapshot, new: newSnapshot)
                        self.accounts[idx].latestSnapshot = newSnapshot
                        self.accounts[idx].errorMsg = nil
                        if account.id == self.selectedAccountID {
                            self.updateCurrentSelectionState()
                        }
                    }
                } catch let error as APIError {
                    let errorMessage: String
                    if error == .missingCookie || error == .unauthorized {
                        AppLogger.shared.log("[\(account.id)] Unauthorized or missing session. Prompting login if active.", level: .warn)
                        errorMessage = "Please log in to \(account.id)."
                        if account.id == requestAccountID {
                            if account.providerType == .claude {
                                LoginWindowController.shared.showLogin()
                            } else if account.providerType == .gemini {
                                GeminiLoginWindowController.shared.showLogin()
                            } else {
                                AntigravityOAuthController.shared.startLogin()
                            }
                        }
                    } else {
                        AppLogger.shared.log("[\(account.id)] API error: \(error.localizedDescription)", level: .error)
                        errorMessage = error.localizedDescription
                    }
                    if let idx = self.accounts.firstIndex(where: { $0.id == account.id }) {
                        self.accounts[idx].latestSnapshot = nil
                        self.accounts[idx].errorMsg = errorMessage
                        if account.id == self.selectedAccountID {
                            self.updateCurrentSelectionState()
                        }
                    }
                } catch {
                    AppLogger.shared.log("[\(account.id)] Unexpected error: \(error.localizedDescription)", level: .error)
                    if let idx = self.accounts.firstIndex(where: { $0.id == account.id }) {
                        self.accounts[idx].latestSnapshot = nil
                        self.accounts[idx].errorMsg = error.localizedDescription
                        if account.id == self.selectedAccountID {
                            self.updateCurrentSelectionState()
                        }
                    }
                }
            }
            
            self.updateCurrentSelectionState()
            self.isLoading = false
        }
    }
    
    func saveCredential() {
        guard !credentialInput.isEmpty else { return }
        if let account = accounts.first(where: { $0.id == selectedAccountID }) {
            account.credentialProvider.saveCredential(credentialInput)
            credentialInput = ""
            showDebugInput = false
            loadData()
        }
    }
    
    func providerIcon(for account: Account? = nil) -> NSImage {
        let target = account ?? accounts.first(where: { $0.id == selectedAccountID })
        guard let target = target else { return NSImage() }
        if target.providerType == .claude {
            return NSWorkspace.shared.icon(forFile: "/Applications/Claude.app")
        } else if target.providerType == .gemini {
            return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Gemini") ?? NSImage()
        } else {
            return NSWorkspace.shared.icon(forFile: "/Applications/Antigravity IDE.app")
        }
    }
    
    private func checkAndNotifyIfNeeded(account: Account, old: UsageSnapshot?, new: UsageSnapshot) {
        AppLogger.shared.log("[Notification] Checking usage thresholds for [\(account.id)]...", level: .info)
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
                        let accountName = account.label ?? account.id
                        let body = "\(accountName) — \(groupContext)\(windowName) window is running low (" + percentStr + "% used)."
                        
                        AppLogger.shared.log("[Notification] Alert triggered for [\(account.id)] (\(windowName) window low: \(percentStr)% used)", level: .warn)
                        sendNotification(title: title, body: body)
                    }
                }
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        AppLogger.shared.log("[Notification] Sending OS notification: '\(title)' - '\(body)'", level: .info)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func updateLaunchAtLoginStatus(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to update SMAppService: \(error)")
        }
    }
}
