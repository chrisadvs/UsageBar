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
                let allWindows = snapshot.groups.flatMap { $0.windows }
                let worstWindow = allWindows.min { $0.percentRemaining < $1.percentRemaining }
                let worstPercent = worstWindow?.percentRemaining ?? .nan
                let worstSeverity = worstWindow?.severity ?? .green
                let label = worstWindow?.kind == .fiveHour ? "5h" : "Wk"

                HStack(spacing: 3) {
                    Image(nsImage: viewModel.providerIcon())
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text("\(label) \(String(format: "%.0f%%", worstPercent))")
                }
                .foregroundColor(color(for: worstSeverity))
            } else {
                HStack(spacing: 3) {
                    Image(nsImage: viewModel.providerIcon())
                        .resizable()
                        .frame(width: 16, height: 16)
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
                Picker("", selection: $viewModel.selectedProvider) {
                    Text("Claude").tag("Claude")
                    Text("Antigravity").tag("Antigravity")
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                Spacer()
            }
            Divider()
            
            if viewModel.isLoading && viewModel.snapshot == nil {
                ProgressView("Loading...")
            } else if let snapshot = viewModel.snapshot {
                VStack(spacing: 12) {
                    ForEach(0..<snapshot.groups.count, id: \.self) { groupIndex in
                        let group = snapshot.groups[groupIndex]
                        if let name = group.name {
                            Text(name).font(.subheadline).foregroundColor(.secondary)
                        }
                        HStack(spacing: 20) {
                            ForEach(0..<group.windows.count, id: \.self) { winIndex in
                                let window = group.windows[winIndex]
                                let title = window.kind == .fiveHour ? "5 Hour" : "7 Day"
                                WindowView(title: title, window: window)
                                if winIndex < group.windows.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        if groupIndex < snapshot.groups.count - 1 {
                            Divider()
                        }
                    }
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
                Button("Debug: Paste Credential") {
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
                    Text("Paste raw credential string:")
                        .font(.caption)
                    TextEditor(text: $viewModel.credentialInput)
                        .frame(height: 60)
                        .border(Color.gray, width: 1)
                    HStack {
                        Spacer()
                        Button("Save & Refresh") {
                            viewModel.saveCredential()
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
    let window: UsageWindow
    
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

