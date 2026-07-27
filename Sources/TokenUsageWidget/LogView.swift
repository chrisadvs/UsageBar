import SwiftUI
import AppKit

struct LogView: View {
    @ObservedObject var logger = AppLogger.shared
    @State private var selectedLevelFilter: String = "ALL"
    
    let filterOptions = ["ALL", "INFO", "WARN", "ERROR"]
    
    var filteredEntries: [LogEntry] {
        if selectedLevelFilter == "ALL" {
            return logger.entries
        } else {
            return logger.entries.filter { $0.level.rawValue == selectedLevelFilter }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("In-App Logs (\(filteredEntries.count) entries)")
                    .font(.headline)
                Spacer()
                Picker("Filter:", selection: $selectedLevelFilter) {
                    ForEach(filterOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filteredEntries.isEmpty {
                        Text("No log entries.")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(filteredEntries) { entry in
                            Text(entry.formattedString)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(color(for: entry.level))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            HStack {
                Button("Copy All") {
                    let text = filteredEntries.map { $0.formattedString }.joined(separator: "\n")
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
                
                Button("Clear Logs") {
                    logger.clear()
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Close") {
                    ConfigurationWindowController.shared.closeWindow()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .frame(minWidth: 350, idealWidth: 440, maxWidth: 480, minHeight: 300, idealHeight: 380, maxHeight: .infinity)
    }
    
    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
