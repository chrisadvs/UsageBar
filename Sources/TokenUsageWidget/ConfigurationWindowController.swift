import AppKit
import SwiftUI

@MainActor
class ConfigurationWindowController: NSObject, NSWindowDelegate {
    static let shared = ConfigurationWindowController()
    
    private var window: NSWindow?
    
    func showWindow(viewModel: WidgetViewModel) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered,
                           defer: false)
        win.title = "Token Usage Configuration"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.minSize = NSSize(width: 440, height: 400)
        
        let configView = ConfigurationView(viewModel: viewModel)
        win.contentView = NSHostingView(rootView: configView)
        
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
