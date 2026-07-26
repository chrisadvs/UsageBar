import Foundation
import Combine
import SwiftUI

public enum LogLevel: String, CaseIterable, Identifiable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    
    public var id: String { rawValue }
}

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    
    public init(timestamp: Date = Date(), level: LogLevel = .info, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
    
    public var formattedString: String {
        let formatter = ISO8601DateFormatter()
        return "[\(formatter.string(from: timestamp))] [\(level.rawValue)] \(message)"
    }
}

public class AppLogger: ObservableObject {
    public static let shared = AppLogger()
    
    @Published public private(set) var entries: [LogEntry] = []
    private var internalEntries: [LogEntry] = []
    public let maxEntries: Int
    private let lock = NSLock()
    
    public init(maxEntries: Int = 300) {
        self.maxEntries = maxEntries
    }
    
    public func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        lock.lock()
        internalEntries.append(entry)
        if internalEntries.count > maxEntries {
            internalEntries.removeFirst(internalEntries.count - maxEntries)
        }
        let updated = internalEntries
        lock.unlock()
        
        if Thread.isMainThread {
            self.entries = updated
        } else {
            DispatchQueue.main.async {
                self.entries = updated
            }
        }
    }
    
    public func clear() {
        lock.lock()
        internalEntries = []
        lock.unlock()
        if Thread.isMainThread {
            self.entries = []
        } else {
            DispatchQueue.main.async {
                self.entries = []
            }
        }
    }
    
    public func formattedLogs() -> String {
        lock.lock()
        let current = self.internalEntries
        lock.unlock()
        return current.map { $0.formattedString }.joined(separator: "\n")
    }
}
