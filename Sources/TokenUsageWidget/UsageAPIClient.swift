import Foundation
import WebKit

public class UsageAPIClient: UsageAPIClientProtocol {
    private let credentialProvider: CredentialProvider
    
    public init(credentialProvider: CredentialProvider) {
        self.credentialProvider = credentialProvider
    }
    
    public static func extractOrgId(from cookies: [HTTPCookie]) -> String? {
        return cookies.first(where: { $0.name == "lastActiveOrg" && !$0.value.isEmpty })?.value
    }
    
    public static func extractOrgId(fromCookieString cookieString: String) -> String? {
        let pairs = cookieString.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for pair in pairs {
            if pair.hasPrefix("lastActiveOrg=") {
                let value = String(pair.dropFirst("lastActiveOrg=".count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
    
    private func getOrgIdFromCookieStore() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: Self.extractOrgId(from: cookies))
                }
            }
        }
    }
    
    public func fetchUsage() async throws -> UsageSnapshot {
        guard let cookie = await credentialProvider.getCredential(), !cookie.isEmpty else {
            throw APIError.missingCookie
        }
        
        var orgId = Self.extractOrgId(fromCookieString: cookie)
        if orgId == nil {
            orgId = await getOrgIdFromCookieStore()
        }
        
        guard let orgId, !orgId.isEmpty else {
            AppLogger.shared.log("[Claude] lastActiveOrg cookie missing. Treating as unauthenticated.", level: .error)
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

        return try await performRequest(request, allowRetry: true)
    }

    /// Claude's API occasionally returns HTTP 200 with an empty body (observed
    /// in real usage, not a 401/403/5xx — a genuinely transient server-side
    /// blip, not an auth or network issue). Retrying once immediately resolves
    /// it in practice; only surface an error to the user if the retry also
    /// comes back empty.
    private func performRequest(_ request: URLRequest, allowRetry: Bool) async throws -> UsageSnapshot {
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

        if data.isEmpty {
            AppLogger.shared.log("[Claude] Got HTTP 200 with an empty body (known transient server-side blip).", level: .warn)
            guard allowRetry else {
                throw APIError.invalidResponse
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await performRequest(request, allowRetry: false)
        }

        do {
            return try UsageParser.parse(json: data)
        } catch {
            // Diagnostic only: this response body is usage numbers/org metadata,
            // not a credential, so it's safe to log — unlike Cookie/token values,
            // which must never be logged. Needed to find out which field Claude's
            // API is intermittently sending as null/missing.
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 data, \(data.count) bytes>"
            AppLogger.shared.log("[Claude] Parse failed: \(error.localizedDescription). Raw body: \(rawBody)", level: .error)
            throw error
        }
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
