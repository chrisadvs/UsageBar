import Foundation

public class GeminiWebUsageAPIClient {
    private let credentialProvider: CredentialProvider
    
    public init(credentialProvider: CredentialProvider) {
        self.credentialProvider = credentialProvider
    }
    
    public func fetchUsage() async throws -> UsageSnapshot {
        guard let credString = await credentialProvider.getCredential(), !credString.isEmpty else {
            throw APIError.missingCookie
        }
        
        guard let credData = credString.data(using: .utf8),
              let creds = try? JSONDecoder().decode(GeminiCredentials.self, from: credData) else {
            throw APIError.missingCookie
        }
        
        guard let url = URL(string: "https://gemini.google.com/_/BardChatUi/data/batchexecute?rpcids=jSf9Qc&source-path=%2Fusage&bl=\(creds.bl)&f.sid=\(creds.fsid)&hl=en&_reqid=\(Int.random(in: 10000...99999))&rt=c") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.addValue(creds.cookieString, forHTTPHeaderField: "Cookie")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let bodyStr = "f.req=[[[\"jSf9Qc\",\"[]\",null,\"generic\"]]]&at=\(creds.at)"
        request.httpBody = bodyStr.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            if let geminiProvider = credentialProvider as? GeminiWebCredentialProvider {
                await MainActor.run {
                    geminiProvider.invalidateCache()
                }
            }
            throw APIError.unauthorized
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        
        do {
            return try GeminiWebUsageParser.parse(string: responseString)
        } catch {
            if let geminiProvider = credentialProvider as? GeminiWebCredentialProvider {
                await MainActor.run {
                    geminiProvider.invalidateCache()
                }
            }
            throw APIError.invalidResponse
        }
    }
}
