import AppKit
import SwiftUI

@MainActor
class TokenStatsWindowController: NSObject, NSWindowDelegate {
    static let shared = TokenStatsWindowController()
    
    private(set) var window: NSWindow?
    
    func showWindow(viewModel: WidgetViewModel) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "UsageBar — Token Statistics (Claude Code)"
        win.center()
        win.isReleasedWhenClosed = false
        win.isRestorable = false
        win.delegate = self
        win.minSize = NSSize(width: 500, height: 450)
        
        let statsView = TokenStatsView(viewModel: viewModel)
        win.contentView = NSHostingView(rootView: statsView)
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeWindow() {
        window?.close()
    }
    
    func windowWillClose(_ notification: Notification) {
        self.window = nil
    }
}
