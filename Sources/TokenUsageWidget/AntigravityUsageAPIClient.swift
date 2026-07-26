import Foundation

public class AntigravityUsageAPIClient: UsageAPIClientProtocol {
    private let credentialProvider: CredentialProvider
    
    public init(credentialProvider: CredentialProvider) {
        self.credentialProvider = credentialProvider
    }
    
    public func fetchUsage() async throws -> UsageSnapshot {
        guard let token = await credentialProvider.getCredential(), !token.isEmpty else {
            throw APIError.missingCookie
        }
        
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        AppLogger.shared.log("[Antigravity] Sending POST request to retrieveUserQuotaSummary...", level: .info)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.shared.log("[Antigravity] Invalid non-HTTP response received.", level: .error)
            throw APIError.invalidResponse
        }
        
        AppLogger.shared.log("[Antigravity] HTTP status code: \(httpResponse.statusCode)", level: httpResponse.statusCode == 200 ? .info : .warn)
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            AppLogger.shared.log("[Antigravity] Unauthorized (401/403). Access token expired or invalid.", level: .error)
            throw APIError.unauthorized
        }
        
        guard httpResponse.statusCode == 200 else {
            AppLogger.shared.log("[Antigravity] Server error status code: \(httpResponse.statusCode)", level: .error)
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try AntigravityUsageParser.parse(json: data)
    }
}
