import Foundation

public enum ProviderType: String, Codable, CaseIterable {
    case claude = "Claude"
    case gemini = "Gemini"
    case antigravity = "Antigravity"
}

public protocol UsageAPIClientProtocol {
    func fetchUsage() async throws -> UsageSnapshot
}

public struct Account: Identifiable {
    public let id: String
    public let providerType: ProviderType
    public var label: String?
    public let credentialProvider: CredentialProvider
    public let apiClient: UsageAPIClientProtocol
    public var latestSnapshot: UsageSnapshot?
    public var errorMsg: String?
    public var isPaused: Bool
    public var isVisibleInMainPanel: Bool
    
    public init(
        id: String,
        providerType: ProviderType,
        label: String? = nil,
        credentialProvider: CredentialProvider,
        apiClient: UsageAPIClientProtocol,
        latestSnapshot: UsageSnapshot? = nil,
        errorMsg: String? = nil,
        isPaused: Bool = false,
        isVisibleInMainPanel: Bool = true
    ) {
        self.id = id
        self.providerType = providerType
        self.label = label
        self.credentialProvider = credentialProvider
        self.apiClient = apiClient
        self.latestSnapshot = latestSnapshot
        self.errorMsg = errorMsg
        self.isPaused = isPaused
        self.isVisibleInMainPanel = isVisibleInMainPanel
    }
}
