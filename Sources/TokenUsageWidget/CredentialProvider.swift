import WebKit

public protocol CredentialProvider {
    func getCredential() async -> String?
    func saveCredential(_ credential: String)
}

public class WKWebViewCredentialProvider: CredentialProvider {
    public init() {}
    
    public func getCredential() async -> String? {
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
    
    public func saveCredential(_ credential: String) {
        // Debug fallback: manually seed the WKWebView cookie jar from a raw
        // "name=value; name2=value2" string pasted from browser DevTools.
        let pairs = credential.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
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
