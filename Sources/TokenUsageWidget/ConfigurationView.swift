import SwiftUI
import ServiceManagement

enum ConfigurationTab: String, CaseIterable {
    case general = "General & Accounts"
    case logs = "Diagnostics & Logs"
}

struct ConfigurationView: View {
    @ObservedObject var viewModel: WidgetViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @State private var showDebugSection = false
    @State private var selectedTab: ConfigurationTab = .general
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: $selectedTab) {
                ForEach(ConfigurationTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
            
            Divider()
            
            if selectedTab == .general {
                generalTabView
            } else {
                LogView()
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 420)
        .onAppear {
            viewModel.updateLaunchAtLoginStatus(launchAtLogin)
        }
    }
    
    private var generalTabView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                // Account Management Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Accounts")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    let activeVisibleCount = viewModel.accounts.filter { $0.isVisibleInMainPanel && !$0.isPaused }.count
                    
                    ForEach(0..<viewModel.accounts.count, id: \.self) { index in
                        let account = viewModel.accounts[index]
                        HStack(spacing: 8) {
                            Image(nsImage: viewModel.providerIcon(for: account))
                                .resizable()
                                .frame(width: 16, height: 16)
                            
                            Text(account.label ?? account.id)
                                .font(.body)
                            
                            if account.isPaused {
                                Text("(Paused - Ticket 14)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { viewModel.accounts[index].isVisibleInMainPanel },
                                set: { newValue in
                                    viewModel.accounts[index].isVisibleInMainPanel = newValue
                                }
                            ))
                            .labelsHidden()
                            .disabled(!account.isPaused && account.isVisibleInMainPanel && activeVisibleCount <= 1)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Divider()
                
                // General Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("General")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            viewModel.updateLaunchAtLoginStatus(newValue)
                        }
                }
                
                #if DEBUG
                Divider()
                
                DisclosureGroup("Debug: Manual Credential Input", isExpanded: $showDebugSection) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste raw credential string for \(viewModel.selectedAccountID):")
                            .font(.caption)
                        TextEditor(text: $viewModel.credentialInput)
                            .frame(height: 50)
                            .border(Color.gray.opacity(0.5), width: 1)
                        HStack {
                            Spacer()
                            Button("Save & Refresh") {
                                viewModel.saveCredential()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.subheadline)
                #endif
                
                Divider()
                
                HStack {
                    Button("Close") {
                        ConfigurationWindowController.shared.closeWindow()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Quit Token Usage") {
                        NSApplication.shared.terminate(nil)
                    }
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
