import Foundation
import CryptoKit

public class AntigravityWebUsageAPIClient: UsageAPIClientProtocol {
    private let credentialProvider: CredentialProvider
    private let apiKeyProvider: AntigravityApiKeyProvider
    private let session: URLSession

    private static let origin = "https://antigravity.google.com"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36"

    public init(credentialProvider: CredentialProvider, apiKeyProvider: AntigravityApiKeyProvider = .shared, session: URLSession = .shared) {
        self.credentialProvider = credentialProvider
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }
    
    public static func authorizationHeader(sapisid: String, origin: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let input = "\(timestamp) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let hash = "\(timestamp)_\(hex)"
        return "SAPISIDHASH \(hash) SAPISID1PHASH \(hash) SAPISID3PHASH \(hash)"
    }
    
    private static func makeRequest(pathAndQuery: String, sapisid: String, cookie: String, apiKey: String, body: Any) -> URLRequest {
        let url = URL(string: "https://antigravity.google.com/$rpc/devtools_jetski_boq_api_proto.ApiService/\(pathAndQuery)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(authorizationHeader(sapisid: sapisid, origin: origin), forHTTPHeaderField: "authorization")
        req.setValue("application/json+protobuf", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("0", forHTTPHeaderField: "x-goog-authuser")
        req.setValue("base64", forHTTPHeaderField: "x-goog-encode-response-if-executable")
        req.setValue(origin, forHTTPHeaderField: "x-origin")
        req.setValue(origin, forHTTPHeaderField: "x-referer")
        req.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }
    
    public func fetchUsage() async throws -> UsageSnapshot {
        guard let credString = await credentialProvider.getCredential(), !credString.isEmpty else {
            throw APIError.missingCookie
        }
        
        guard let credData = credString.data(using: .utf8),
              let creds = try? JSONDecoder().decode(AntigravityCredentials.self, from: credData) else {
            throw APIError.missingCookie
        }

        guard let apiKey = await apiKeyProvider.getApiKey() else {
            AppLogger.shared.log("[Antigravity] Failed to obtain API key dynamically from live frontend.", level: .error)
            throw APIError.missingApiKey
        }

        // 1. ListInstances to find an online instance (status == 1)
        let listInstancesReq = Self.makeRequest(
            pathAndQuery: "ListInstances",
            sapisid: creds.sapisid,
            cookie: creds.cookieString,
            apiKey: apiKey,
            body: [Any]()
        )
        
        AppLogger.shared.log("[Antigravity] Sending POST request to ListInstances...", level: .info)
        let (listData, listResponse) = try await session.data(for: listInstancesReq)
        
        guard let listHttpResponse = listResponse as? HTTPURLResponse else {
            AppLogger.shared.log("[Antigravity] Invalid non-HTTP response received for ListInstances.", level: .error)
            throw APIError.invalidResponse
        }
        
        AppLogger.shared.log("[Antigravity] ListInstances HTTP status code: \(listHttpResponse.statusCode)", level: listHttpResponse.statusCode == 200 ? .info : .warn)
        
        if listHttpResponse.statusCode == 401 || listHttpResponse.statusCode == 403 {
            AppLogger.shared.log("[Antigravity] Unauthorized (401/403) on ListInstances. Invalidating cookie and API key cache.", level: .error)
            if let antigravityProvider = credentialProvider as? AntigravityWebCredentialProvider {
                await MainActor.run {
                    antigravityProvider.invalidateCache()
                }
            }
            _ = await apiKeyProvider.getApiKey(force: true)
            throw APIError.unauthorized
        }
        
        guard listHttpResponse.statusCode == 200 else {
            AppLogger.shared.log("[Antigravity] ListInstances server error status code: \(listHttpResponse.statusCode)", level: .error)
            throw APIError.serverError(statusCode: listHttpResponse.statusCode)
        }
        
        guard let instances = try? JSONSerialization.jsonObject(with: listData, options: [.fragmentsAllowed]),
              let outer = instances as? [[Any]],
              let list = outer.first as? [[Any]] else {
            AppLogger.shared.log("[Antigravity] Failed to parse ListInstances response structure.", level: .error)
            throw APIError.invalidResponse
        }
        
        var onlineId: String?
        for entry in list {
            guard entry.count >= 3, let id = entry[0] as? String else { continue }
            let status = entry[2] as? Int
            if status == 1 {
                onlineId = id
            }
        }
        
        guard let instanceId = onlineId else {
            AppLogger.shared.log("[Antigravity] No online instance found (status == 1).", level: .warn)
            throw APIError.invalidResponse
        }
        
        // 2. RetrieveUserQuotaSummary with online instanceId
        let innerBodyB64 = Data("{\"forceRefresh\":true}".utf8).base64EncodedString()
        let quotaBody: [Any] = [
            instanceId,
            "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
            innerBodyB64,
            [["x-is-streaming", "false"], ["x-jetski-remote-control-user-agent", Self.userAgent]]
        ]
        let quotaReq = Self.makeRequest(
            pathAndQuery: "ProxyCommand?$unique=RetrieveUserQuotaSummary",
            sapisid: creds.sapisid,
            cookie: creds.cookieString,
            apiKey: apiKey,
            body: quotaBody
        )
        
        AppLogger.shared.log("[Antigravity] Sending POST request to RetrieveUserQuotaSummary (instance: \(instanceId))...", level: .info)
        let (quotaData, quotaResponse) = try await session.data(for: quotaReq)
        
        guard let quotaHttpResponse = quotaResponse as? HTTPURLResponse else {
            AppLogger.shared.log("[Antigravity] Invalid non-HTTP response received for RetrieveUserQuotaSummary.", level: .error)
            throw APIError.invalidResponse
        }
        
        AppLogger.shared.log("[Antigravity] RetrieveUserQuotaSummary HTTP status code: \(quotaHttpResponse.statusCode)", level: quotaHttpResponse.statusCode == 200 ? .info : .warn)
        
        if quotaHttpResponse.statusCode == 401 || quotaHttpResponse.statusCode == 403 {
            AppLogger.shared.log("[Antigravity] Unauthorized (401/403) on RetrieveUserQuotaSummary. Invalidating cookie and API key cache.", level: .error)
            if let antigravityProvider = credentialProvider as? AntigravityWebCredentialProvider {
                await MainActor.run {
                    antigravityProvider.invalidateCache()
                }
            }
            _ = await apiKeyProvider.getApiKey(force: true)
            throw APIError.unauthorized
        }
        
        guard quotaHttpResponse.statusCode == 200 else {
            AppLogger.shared.log("[Antigravity] RetrieveUserQuotaSummary server error status code: \(quotaHttpResponse.statusCode)", level: .error)
            throw APIError.serverError(statusCode: quotaHttpResponse.statusCode)
        }
        
        guard let quotaResp = try? JSONSerialization.jsonObject(with: quotaData, options: [.fragmentsAllowed]),
              let arr = quotaResp as? [Any],
              let b64String = arr.first as? String,
              let decodedData = Data(base64Encoded: b64String) else {
            AppLogger.shared.log("[Antigravity] Failed to extract base64 payload from RetrieveUserQuotaSummary response.", level: .error)
            throw APIError.invalidResponse
        }
        
        do {
            return try AntigravityWebUsageParser.parse(data: decodedData)
        } catch {
            AppLogger.shared.log("[Antigravity] Parse error: \(error.localizedDescription). Invalidating cache.", level: .error)
            if let antigravityProvider = credentialProvider as? AntigravityWebCredentialProvider {
                await MainActor.run {
                    antigravityProvider.invalidateCache()
                }
            }
            throw APIError.invalidResponse
        }
    }
}
