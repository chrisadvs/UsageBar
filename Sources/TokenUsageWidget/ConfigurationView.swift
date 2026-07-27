import SwiftUI
import ServiceManagement

struct ConfigurationView: View {
    @ObservedObject var viewModel: WidgetViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @State private var showDebugSection = false
    @State private var showLogs = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Configuration")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            Divider()
            
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
            
            Divider()
            
            // Diagnostics Section (Ticket 21)
            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostics")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("In-App Log & Error Inspector")
                        .font(.body)
                    Spacer()
                    Button("View Logs...") {
                        showLogs = true
                    }
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
                Spacer()
                Button("Quit Token Usage") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 340)
        .popover(isPresented: $showLogs, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
            LogView()
        }
        .onAppear {
            viewModel.updateLaunchAtLoginStatus(launchAtLogin)
        }
    }
}
