import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TokenUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = WidgetViewModel()
    
    var body: some Scene {
        MenuBarExtra("Token Usage", systemImage: "bolt.fill") {
            ContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: WidgetViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading && viewModel.snapshot == nil {
                ProgressView("Loading...")
            } else if let snapshot = viewModel.snapshot {
                HStack(spacing: 20) {
                    WindowView(title: "5 Hour", window: snapshot.fiveHour)
                    Divider()
                    WindowView(title: "7 Day", window: snapshot.sevenDay)
                }
            } else if let error = viewModel.errorMsg {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("No data available.")
                    .foregroundColor(.gray)
            }
            
            Divider()
            
            HStack {
                Button(action: { viewModel.loadData() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                Button("Debug: Paste Cookie") {
                    viewModel.showDebugInput.toggle()
                }
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            
            if viewModel.showDebugInput {
                VStack(alignment: .leading) {
                    Text("Paste raw cookie string (starts with _fbp=...):")
                        .font(.caption)
                    TextEditor(text: $viewModel.cookieInput)
                        .frame(height: 60)
                        .border(Color.gray, width: 1)
                    HStack {
                        Spacer()
                        Button("Save Cookie & Refresh") {
                            viewModel.saveCookie()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            viewModel.loadData()
        }
    }
}

struct WindowView: View {
    let title: String
    let window: WindowState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            
            HStack {
                Text(String(format: "%.1f%% rem", window.percentRemaining))
                    .font(.title2.bold())
                    .foregroundColor(color(for: window.severity))
            }
            
            Text("Resets in \(window.resetsAtFormatted)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func color(for severity: Severity) -> Color {
        switch severity {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }
}

