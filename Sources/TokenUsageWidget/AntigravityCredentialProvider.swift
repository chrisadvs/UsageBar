import Foundation
import Security

public class AntigravityCredentialProvider: CredentialProvider {
    public static let shared = AntigravityCredentialProvider()
    
    private var manualToken: String?
    private var currentAccessToken: String?
    private var accessTokenExpiry: Date?
    
    public init() {}
    
    public func getCredential() async -> String? {
        if let manual = manualToken {
            return manual
        }
        
        if let token = currentAccessToken, let expiry = accessTokenExpiry, Date() < expiry {
            return token
        }
        
        if let refreshToken = getRefreshToken() {
            do {
                let newToken = try await refreshAccessToken(refreshToken: refreshToken)
                return newToken
            } catch {
                return nil
            }
        }
        
        return nil
    }
    
    public func saveCredential(_ credential: String) {
        self.manualToken = credential
    }
    
    public func setAccessToken(_ token: String, expiry: Date) {
        self.currentAccessToken = token
        self.accessTokenExpiry = expiry
    }
    
    public func saveRefreshToken(_ token: String) {
        let account = "com.chris.TokenUsageWidget.AntigravityRefreshToken"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: token.data(using: .utf8)!
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    public func getRefreshToken() -> String? {
        let account = "com.chris.TokenUsageWidget.AntigravityRefreshToken"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    var urlSession: URLSession = .shared
    
    func refreshAccessToken(refreshToken: String) async throws -> String {
        AppLogger.shared.log("[Antigravity] Attempting OAuth access token refresh...", level: .info)
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let clientId = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.shared.log("[Antigravity] Invalid non-HTTP response during token refresh.", level: .error)
            throw APIError.invalidResponse
        }
        
        AppLogger.shared.log("[Antigravity] Token refresh HTTP status: \(httpResponse.statusCode)", level: httpResponse.statusCode == 200 ? .info : .error)
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.unauthorized
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            AppLogger.shared.log("[Antigravity] Failed to decode access_token from refresh response.", level: .error)
            throw APIError.invalidResponse
        }
        
        let expiresIn = (json["expires_in"] as? Double) ?? 3599.0
        let expiryDate = Date().addingTimeInterval(expiresIn - 60)
        setAccessToken(accessToken, expiry: expiryDate)
        
        AppLogger.shared.log("[Antigravity] OAuth access token successfully refreshed.", level: .info)
        return accessToken
    }
}
