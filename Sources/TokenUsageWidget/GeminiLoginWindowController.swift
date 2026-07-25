import AppKit
import WebKit

@MainActor
public class GeminiLoginWindowController: NSObject, WKNavigationDelegate {
    public static let shared = GeminiLoginWindowController()
    
    private var window: NSWindow?
    private var webView: WKWebView?
    public var onLoginSuccess: (() -> Void)?
    
    public func showLogin() {
        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered,
                               defer: false)
            win.title = "Log in to Gemini"
            win.center()
            win.isReleasedWhenClosed = false
            
            let wv = WKWebView(frame: win.contentView!.bounds)
            wv.autoresizingMask = [.width, .height]
            wv.navigationDelegate = self
            win.contentView?.addSubview(wv)
            
            self.webView = wv
            self.window = win
        }
        
        if let url = URL(string: "https://gemini.google.com/app") {
            webView?.load(URLRequest(url: url))
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        if url.starts(with: "https://gemini.google.com/app") {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                let hasCookie = cookies.contains { $0.domain.contains("google.com") }
                if hasCookie {
                    DispatchQueue.main.async {
                        self?.window?.close()
                        self?.onLoginSuccess?()
                    }
                }
            }
        }
    }
}
