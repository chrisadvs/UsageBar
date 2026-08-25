import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // Register/verify the login item here, not only in the menu bar
        // panel's onAppear — onAppear only fires once the user actually
        // clicks the menu bar icon to open the panel, so a user who enables
        // "Launch at Login" and never reopens the panel would otherwise
        // never actually get registered.
        let launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
        WidgetViewModel.updateLaunchAtLoginStatus(launchAtLogin)
    }
}

@main
struct TokenUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = WidgetViewModel()

    var body: some Scene {
        MenuBarExtra {
            // .id() forces SwiftUI to treat this as a fresh view whenever the
            // selected account changes, which in turn makes MenuBarExtra's
            // auto-generated backing window re-measure its height. Without
            // this, the window only ever grows to fit the largest content
            // seen so far and never shrinks back down when switching to an
            // account with fewer usage windows (e.g. Antigravity's 2 groups
            // vs. Claude/Gemini's 1).
            ContentView(viewModel: viewModel)
                .id(viewModel.selectedAccountID)
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
                    Text("UB")
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
            
            if viewModel.selectedAccountID == "Claude" && viewModel.isClaudeCodeInstalled {
                Divider()
                TokenUsageSummaryRow(viewModel: viewModel)
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
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            viewModel.loadData()
            WidgetViewModel.updateLaunchAtLoginStatus(launchAtLogin)
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
                Text(String(format: "%.1f%% left", window.percentRemaining))
                    .font(.title2.bold())
                    .foregroundColor(color(for: window.severity))
            }
            
            if let absolute = window.resetsAtAbsolute {
                Text("Resets at \(absolute)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("in \(window.resetsAtFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(window.resetsAtFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

struct TokenUsageSummaryRow: View {
    @ObservedObject var viewModel: WidgetViewModel
    
    var body: some View {
        Button(action: {
            TokenStatsWindowController.shared.showWindow(viewModel: viewModel)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("5h Tokens:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let summary = viewModel.tokenUsage[.currentFiveHourWindow] {
                    if viewModel.isScanningTranscripts && summary.isPartial {
                        Text("Indexing…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if viewModel.isFiveHourWindowAvailable {
                        HStack(spacing: 6) {
                            Text(TokenFormatter.formatCompact(summary.counts.total))
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            
                            if let cost = summary.estimatedCostUSD {
                                Text("(\(TokenFormatter.formatUSD(cost)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("—")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.isScanningTranscripts {
                    Text("Indexing…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("View Token Usage Stats")
    }
}


