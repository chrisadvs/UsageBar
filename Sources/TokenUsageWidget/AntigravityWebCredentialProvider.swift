import Foundation
import WebKit

public struct AntigravityCredentials: Codable {
    public let sapisid: String
    public let cookieString: String
    
    public init(sapisid: String, cookieString: String) {
        self.sapisid = sapisid
        self.cookieString = cookieString
    }
}

@MainActor
public class AntigravityWebCredentialProvider: NSObject, CredentialProvider, WKNavigationDelegate {
    private var cachedCredentials: AntigravityCredentials?
    private var fetchContinuations: [CheckedContinuation<String?, Never>] = []
    private var webView: WKWebView?
    private var isFetching = false
    
    public override init() {
        super.init()
    }
    
    public func invalidateCache() {
        cachedCredentials = nil
    }
    
    public func getCredential() async -> String? {
        if let cached = cachedCredentials {
            if let data = try? JSONEncoder().encode(cached) {
                return String(data: data, encoding: .utf8)
            }
        }
        
        // Fast path: check if cookie store already has SAPISID
        if let creds = await extractCredentialsFromStore() {
            self.cachedCredentials = creds
            if let data = try? JSONEncoder().encode(creds) {
                return String(data: data, encoding: .utf8)
            }
        }
        
        return await withCheckedContinuation { continuation in
            fetchContinuations.append(continuation)
            
            if !isFetching {
                isFetching = true
                let wv = WKWebView(frame: .zero)
                self.webView = wv
                wv.navigationDelegate = self
                wv.load(URLRequest(url: URL(string: "https://antigravity.google.com")!))
            }
        }
    }
    
    public func saveCredential(_ credential: String) {
        // Not used for Antigravity directly in this widget since we extract from WKWebView natively.
    }
    
    private func extractCredentialsFromStore() async -> AntigravityCredentials? {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                guard let sapisid = cookies.first(where: { $0.name == "SAPISID" && $0.domain.contains("google.com") && !$0.value.isEmpty }) else {
                    continuation.resume(returning: nil)
                    return
                }
                let relevant = cookies.filter { $0.domain.contains("google.com") }
                let cookieString = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                if cookieString.isEmpty {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: AntigravityCredentials(sapisid: sapisid.value, cookieString: cookieString))
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            if let creds = await self.extractCredentialsFromStore() {
                self.cachedCredentials = creds
                if let data = try? JSONEncoder().encode(creds) {
                    self.finish(with: String(data: data, encoding: .utf8))
                    return
                }
            }
            self.finish(with: nil)
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }
    
    private func finish(with result: String?) {
        for continuation in fetchContinuations {
            continuation.resume(returning: result)
        }
        fetchContinuations.removeAll()
        isFetching = false
        webView = nil
    }
}
