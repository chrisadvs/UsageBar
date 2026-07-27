import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
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
            HStack(spacing: 6) {
                ForEach(viewModel.accounts.filter { $0.isVisibleInMainPanel }) { account in
                    let isSelected = (viewModel.selectedAccountID == account.id)
                    
                    Button(action: {
                        if !account.isPaused {
                            viewModel.selectedAccountID = account.id
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(nsImage: viewModel.providerIcon(for: account))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(account.label ?? account.id)
                                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                                .foregroundColor(isSelected ? .white : .primary)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.ultraThinMaterial))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isSelected ? Color.white.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: isSelected ? Color.black.opacity(0.15) : Color.clear, radius: 1, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(account.isPaused)
                    .opacity(account.isPaused ? 0.4 : 1.0)
                }
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
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    ConfigurationWindowController.shared.showWindow(viewModel: viewModel)
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Configuration")
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            viewModel.loadData()
            viewModel.updateLaunchAtLoginStatus(launchAtLogin)
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

