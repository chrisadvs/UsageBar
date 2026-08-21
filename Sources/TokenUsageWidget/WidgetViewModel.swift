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
    @Published var snapshot: UsageSnapshot?
    @Published var errorMsg: String?
    @Published var isLoading = false
    
    // Token usage statistics
    @Published var tokenUsage: [TokenUsageScope: TokenUsageSummary] = [:]
    @Published var isScanningTranscripts = false
    @Published var trendBuckets: [TokenUsageScope: [TrendBucket]] = [:]
    @Published var lastTokenScanDate: Date?
    private let tokenUsageStore = TokenUsageStore.shared
    
    // Debug properties for manual credential input
    @Published var credentialInput: String = ""
    @Published var showDebugInput = false
    
    init() {
        let storedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? "Claude"
        self.selectedAccountID = storedProvider

        let claudeCreds = WKWebViewCredentialProvider()
        let geminiCreds = GeminiWebCredentialProvider()

        let claudeClient = UsageAPIClient(credentialProvider: claudeCreds)
        let geminiClient = GeminiWebUsageAPIClient(credentialProvider: geminiCreds)

        let savedVisibleIDs = UserDefaults.standard.array(forKey: "visibleAccountIDs") as? [String]

        self.accounts = [
            Account(id: "Claude", providerType: .claude, credentialProvider: claudeCreds, apiClient: claudeClient, isPaused: false, isVisibleInMainPanel: savedVisibleIDs?.contains("Claude") ?? true),
            Account(id: "Gemini", providerType: .gemini, credentialProvider: geminiCreds, apiClient: geminiClient, isPaused: false, isVisibleInMainPanel: savedVisibleIDs?.contains("Gemini") ?? true)
        ]

        updateCurrentSelectionState()
        requestNotificationPermission()
        startPolling()

        LoginWindowController.shared.onLoginSuccess = { [weak self] in
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
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
                AppLogger.shared.log("Notification permission error: \(error.localizedDescription)", level: .error)
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
    
    var isClaudeCodeInstalled: Bool {
        FileManager.default.fileExists(atPath: TokenUsageStore.defaultTranscriptsDirectory.path)
    }
    
    var fiveHourResetsAtDate: Date? {
        accounts.first(where: { $0.providerType == .claude })?.latestSnapshot?.fiveHour.resetsAtDate
    }
    
    var isFiveHourWindowAvailable: Bool {
        fiveHourResetsAtDate != nil
    }
    
    func refreshTokenUsage(forcePricingRefresh: Bool = false) {
        guard !isScanningTranscripts else { return }
        isScanningTranscripts = true
        
        Task {
            let windowStart: Date?
            if let resetsAt = self.fiveHourResetsAtDate {
                windowStart = resetsAt.addingTimeInterval(-5 * 3600)
            } else {
                windowStart = nil
            }
            
            let summaries = await self.tokenUsageStore.refresh(
                fiveHourWindowStart: windowStart,
                now: Date(),
                forcePricingRefresh: forcePricingRefresh
            )
            let trends = await self.tokenUsageStore.getAllTrendBuckets(
                fiveHourWindowStart: windowStart,
                now: Date()
            )

            self.tokenUsage = summaries
            self.trendBuckets = trends
            self.lastTokenScanDate = Date()
            self.isScanningTranscripts = false
        }
    }
    
    func loadData() {
        // Refresh token usage in parallel without being blocked by isLoading
        refreshTokenUsage()
        
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
            
            // Re-evaluate 5-hour window start if Claude quota was just refreshed
            if self.isClaudeCodeInstalled {
                self.refreshTokenUsage()
            }
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
    
    /// Prefers the real installed app's own icon when present (a nice bonus for
    /// users who have the desktop app), but this app never requires that desktop
    /// app to be installed — it only ever talks to the web session. Falls back to
    /// a bundled SF Symbol so the icon is never broken/missing for users who don't
    /// have the desktop app, or have it installed somewhere non-standard.
    func providerIcon(for account: Account? = nil) -> NSImage {
        let target = account ?? accounts.first(where: { $0.id == selectedAccountID })
        guard let target = target else { return NSImage() }
        switch target.providerType {
        case .claude:
            return installedAppIcon(atPath: "/Applications/Claude.app")
                ?? NSImage(systemSymbolName: "bubble.left.and.text.bubble.right.fill", accessibilityDescription: "Claude")
                ?? NSImage()
        case .gemini:
            return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Gemini") ?? NSImage()
        }
    }

    private func installedAppIcon(atPath path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
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
    
    static func updateLaunchAtLoginStatus(_ enabled: Bool) {
        do {
            if enabled {
                // .notFound (not just .notRegistered) needs a fresh register() call too —
                // observed in practice on an ad-hoc-signed, non-notarized build; only
                // checking .notRegistered silently skipped registration in that state.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to update SMAppService: \(error)")
            AppLogger.shared.log("Failed to update SMAppService: \(error.localizedDescription)", level: .error)
        }
    }
}
