import Foundation
import WebKit

public struct GeminiCredentials: Codable {
    public let fsid: String
    public let bl: String
    public let at: String
    public let cookieString: String
}

@MainActor
public class GeminiWebCredentialProvider: NSObject, CredentialProvider, WKNavigationDelegate {
    private var cachedCredentials: GeminiCredentials?
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
        
        return await withCheckedContinuation { continuation in
            fetchContinuations.append(continuation)
            
            if !isFetching {
                isFetching = true
                let wv = WKWebView(frame: .zero)
                self.webView = wv
                wv.navigationDelegate = self
                wv.load(URLRequest(url: URL(string: "https://gemini.google.com/app")!))
            }
        }
    }
    
    public func saveCredential(_ credential: String) {
        // Not used for Gemini directly in this widget since we extract from WKWebView natively.
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host == "gemini.google.com" else {
            finish(with: nil)
            return
        }
        
        if url.path == "/app" || url.path.starts(with: "/app/") {
            // Delay for JS vars to populate
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.extractTokens(from: webView)
            }
        } else {
            // E.g., on a login page
            finish(with: nil)
        }
    }
    
    private func extractTokens(from webView: WKWebView) {
        let js = """
        (function() {
            let html = document.documentElement.innerHTML;
            let result = {};
            let fsidMatch = html.match(/"f\\\\.sid","([^"]+)"/);
            if (fsidMatch) { result.fsid = fsidMatch[1]; }
            let blMatch = html.match(/"cfb2h","([^"]+)"/) || html.match(/"bl","([^"]+)"/);
            let atMatch = html.match(/"SNlM0e","([^"]+)"/);
            if (blMatch) { result.bl = blMatch[1]; }
            if (atMatch) { result.at = atMatch[1]; }
            if (window.WIZ_global_data) {
                result.wiz_fsid = window.WIZ_global_data["FdrFJe"];
                result.wiz_bl = window.WIZ_global_data["cfb2h"];
                result.wiz_at = window.WIZ_global_data["SNlM0e"];
            }
            return result;
        })();
        """
        
        webView.evaluateJavaScript(js) { [weak self] (res, err) in
            guard let self = self else { return }
            if let dict = res as? [String: Any] {
                let fsid = dict["fsid"] as? String ?? dict["wiz_fsid"] as? String
                let bl = dict["bl"] as? String ?? dict["wiz_bl"] as? String
                let at = dict["at"] as? String ?? dict["wiz_at"] as? String
                
                if let fsid = fsid, let bl = bl, let at = at {
                    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                        let cookieString = cookies.map { $0.name + "=" + $0.value }.joined(separator: "; ")
                        if cookieString.isEmpty {
                            self.finish(with: nil)
                            return
                        }
                        
                        let creds = GeminiCredentials(fsid: fsid, bl: bl, at: at, cookieString: cookieString)
                        self.cachedCredentials = creds
                        if let data = try? JSONEncoder().encode(creds) {
                            self.finish(with: String(data: data, encoding: .utf8))
                        } else {
                            self.finish(with: nil)
                        }
                    }
                    return
                }
            }
            self.finish(with: nil)
        }
    }
    
    private func finish(with result: String?) {
        for continuation in fetchContinuations {
            continuation.resume(returning: result)
        }
        fetchContinuations.clear()
        isFetching = false
        webView = nil
    }
}

extension Array {
    mutating func clear() {
        self.removeAll()
    }
}
