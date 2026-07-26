import Foundation

public class UsageAPIClient: UsageAPIClientProtocol {
    private let credentialProvider: CredentialProvider
    private let orgId: String
    
    public init(credentialProvider: CredentialProvider, orgId: String) {
        self.credentialProvider = credentialProvider
        self.orgId = orgId
    }
    
    public func fetchUsage() async throws -> UsageSnapshot {
        guard let cookie = await credentialProvider.getCredential(), !cookie.isEmpty else {
            throw APIError.missingCookie
        }
        
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(cookie, forHTTPHeaderField: "cookie")
        // Mimic standard headers slightly just in case
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36", forHTTPHeaderField: "user-agent")
        
        AppLogger.shared.log("[Claude] Sending GET request to usage API...", level: .info)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.shared.log("[Claude] Invalid non-HTTP response received.", level: .error)
            throw APIError.invalidResponse
        }
        
        AppLogger.shared.log("[Claude] HTTP status code: \(httpResponse.statusCode)", level: httpResponse.statusCode == 200 ? .info : .warn)
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            AppLogger.shared.log("[Claude] Unauthorized (401/403). Session cookie expired.", level: .error)
            throw APIError.unauthorized
        }
        
        guard httpResponse.statusCode == 200 else {
            AppLogger.shared.log("[Claude] Server error status code: \(httpResponse.statusCode)", level: .error)
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try UsageParser.parse(json: data)
    }
}

public enum APIError: Error, LocalizedError, Equatable {
    case missingCookie
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int)
    
    public var errorDescription: String? {
        switch self {
        case .missingCookie:
            return "No cookie found. Please paste your cookie in Debug mode."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .unauthorized:
            return "Unauthorized (401/403). Cookie might be expired."
        case .serverError(let code):
            return "Server error: \(code)."
        }
    }
}
