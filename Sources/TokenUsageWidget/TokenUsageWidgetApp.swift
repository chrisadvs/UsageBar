import SwiftUI
import ServiceManagement

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
        MenuBarExtra {
            ContentView(viewModel: viewModel)
        } label: {
            if let snapshot = viewModel.snapshot {
                let worstPercent = min(snapshot.fiveHour.percentRemaining, snapshot.sevenDay.percentRemaining)
                let worstSeverity = snapshot.fiveHour.severity == .red || snapshot.sevenDay.severity == .red ? Severity.red :
                                    (snapshot.fiveHour.severity == .yellow || snapshot.sevenDay.severity == .yellow ? Severity.yellow : Severity.green)

                HStack(spacing: 3) {
                    Image("MenuBarIcon")
                    Text(String(format: "%.0f%%", worstPercent))
                }
                .foregroundColor(color(for: worstSeverity))
            } else {
                HStack(spacing: 3) {
                    Image("MenuBarIcon")
                    Text("TU")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
    
    private func color(for severity: Severity) -> Color {
        switch severity {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: WidgetViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Provider:")
                    .font(.headline)
                Picker("", selection: .constant("Claude")) {
                    Text("Claude").tag("Claude")
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                Spacer()
            }
            Divider()
            
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

                #if DEBUG
                Button("Debug: Paste Cookie") {
                    viewModel.showDebugInput.toggle()
                }
                #endif
            }
            
            HStack {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLoginStatus(newValue)
                    }
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            
            #if DEBUG
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
            #endif
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            viewModel.loadData()
            updateLaunchAtLoginStatus(launchAtLogin)
        }
    }
    
    private func updateLaunchAtLoginStatus(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to update SMAppService: \\(error)")
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

