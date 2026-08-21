import AppKit
import WebKit

@MainActor
public class LoginWindowController: NSObject, WKNavigationDelegate {
    public static let shared = LoginWindowController()
    
    private var window: NSWindow?
    private var webView: WKWebView?
    public var onLoginSuccess: (() -> Void)?
    
    public func showLogin() {
        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered,
                               defer: false)
            win.title = "Log in to Claude"
            win.center()
            win.isReleasedWhenClosed = false
            win.isRestorable = false
            
            let wv = WKWebView(frame: win.contentView!.bounds)
            wv.autoresizingMask = [.width, .height]
            wv.navigationDelegate = self
            win.contentView?.addSubview(wv)
            
            self.webView = wv
            self.window = win
        }
        
        if let url = URL(string: "https://claude.ai/login") {
            webView?.load(URLRequest(url: url))
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Once navigated to the chat page, check for cookie
        if let url = webView.url?.absoluteString, url.starts(with: "https://claude.ai/chat") || url.starts(with: "https://claude.ai/projects") {
            // Login successful, fetch cookies
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                let hasSession = cookies.contains { $0.name == "sessionKey" }
                if hasSession {
                    DispatchQueue.main.async {
                        self?.window?.close()
                        self?.onLoginSuccess?()
                    }
                }
            }
        }
    }
}
