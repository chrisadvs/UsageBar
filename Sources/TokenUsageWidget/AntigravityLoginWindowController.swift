import AppKit
import WebKit

@MainActor
public class AntigravityLoginWindowController: NSObject, WKNavigationDelegate {
    public static let shared = AntigravityLoginWindowController()
    
    private var window: NSWindow?
    private var webView: WKWebView?
    public var onLoginSuccess: (() -> Void)?
    
    public func showLogin() {
        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered,
                               defer: false)
            win.title = "Log in to Antigravity"
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
        
        if let url = URL(string: "https://antigravity.google.com") {
            webView?.load(URLRequest(url: url))
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let hasAuthCookie = cookies.contains { cookie in
                cookie.domain.contains("google.com") && cookie.name == "SAPISID" && !cookie.value.isEmpty
            }
            if hasAuthCookie {
                DispatchQueue.main.async {
                    self?.window?.close()
                    self?.onLoginSuccess?()
                }
            }
        }
    }
}
