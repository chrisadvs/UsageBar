import WebKit

public protocol CredentialProvider {
    func getCookie() async -> String?
    func saveCookie(_ cookie: String)
}

public class WKWebViewCredentialProvider: CredentialProvider {
    public init() {}
    
    public func getCookie() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    // Claude uses several cookies, but sessionKey is the most critical.
                    // Joining all of them is standard.
                    let cookieString = cookies.map { $0.name + "=" + $0.value }.joined(separator: "; ")
                    continuation.resume(returning: cookieString.isEmpty ? nil : cookieString)
                }
            }
        }
    }
    
    public func saveCookie(_ cookie: String) {
        // Debug fallback: manually seed the WKWebView cookie jar from a raw
        // "name=value; name2=value2" string pasted from browser DevTools.
        let pairs = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for pair in pairs {
            guard let equalsIndex = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[pair.startIndex..<equalsIndex])
            let value = String(pair[pair.index(after: equalsIndex)...])
            guard !name.isEmpty else { continue }

            if let httpCookie = HTTPCookie(properties: [
                .domain: ".claude.ai",
                .path: "/",
                .name: name,
                .value: value,
                .secure: true
            ]) {
                WKWebsiteDataStore.default().httpCookieStore.setCookie(httpCookie)
            }
        }
    }
}

public class KeychainCredentialProvider: CredentialProvider {
    private let service = "claude.ai"
    private let account = "session_cookie"
    
    public init() {}
    
    public func getCookie() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    public func saveCookie(_ cookie: String) {
        guard let data = cookie.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var addQuery = query
        addQuery[kSecValueData as String] = data
        
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
