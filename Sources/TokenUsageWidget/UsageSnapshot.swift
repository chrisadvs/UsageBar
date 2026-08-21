import Foundation

public enum WindowKind: Equatable {
    case fiveHour
    case weekly

    /// Display sort priority. Lower sorts first. Use this instead of ad-hoc
    /// pairwise comparators, which silently misorder once a third case exists.
    var sortOrder: Int {
        switch self {
        case .fiveHour: return 0
        case .weekly: return 1
        }
    }
}

public struct UsageWindow: Equatable {
    public let kind: WindowKind
    public let percentRemaining: Double
    public let severity: Severity
    public let resetsAtFormatted: String
    public let resetsAtAbsolute: String?
    public let resetsAtDate: Date?
    
    public init(kind: WindowKind, percentRemaining: Double, severity: Severity, resetsAtFormatted: String, resetsAtAbsolute: String?, resetsAtDate: Date? = nil) {
        self.kind = kind
        self.percentRemaining = percentRemaining
        self.severity = severity
        self.resetsAtFormatted = resetsAtFormatted
        self.resetsAtAbsolute = resetsAtAbsolute
        self.resetsAtDate = resetsAtDate
    }
}

public enum ResetTimeFormatter {
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    private static let weekdayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE jmm")
        return formatter
    }()
    
    private static let monthDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd jmm")
        return formatter
    }()
    
    public static func absolute(_ resetsAt: Date, now: Date, calendar: Calendar = .current) -> String {
        let startOfNow = calendar.startOfDay(for: now)
        let startOfResetsAt = calendar.startOfDay(for: resetsAt)
        let dayDiff = calendar.dateComponents([.day], from: startOfNow, to: startOfResetsAt).day ?? 0
        
        if dayDiff == 0 {
            return shortTimeFormatter.string(from: resetsAt)
        } else if dayDiff == 1 {
            return "Tomorrow \(shortTimeFormatter.string(from: resetsAt))"
        } else if dayDiff >= 2 && dayDiff <= 6 {
            return weekdayTimeFormatter.string(from: resetsAt)
        } else {
            return monthDateTimeFormatter.string(from: resetsAt)
        }
    }
}

public enum Severity: Equatable {
    case green, yellow, red
}

public struct UsageGroup: Equatable {
    public let name: String?
    public let windows: [UsageWindow]
    
    public init(name: String?, windows: [UsageWindow]) {
        self.name = name
        self.windows = windows
    }
}

public struct UsageSnapshot: Equatable {
    public let groups: [UsageGroup]
    
    public init(groups: [UsageGroup]) {
        self.groups = groups
    }
    
    // For backward compatibility / Claude specific tests
    public var fiveHour: UsageWindow {
        return groups.first?.windows.first { $0.kind == .fiveHour } ?? UsageWindow(kind: .fiveHour, percentRemaining: .nan, severity: .green, resetsAtFormatted: "", resetsAtAbsolute: nil)
    }
    
    public var sevenDay: UsageWindow {
        return groups.first?.windows.first { $0.kind == .weekly } ?? UsageWindow(kind: .weekly, percentRemaining: .nan, severity: .green, resetsAtFormatted: "", resetsAtAbsolute: nil)
    }
}

public struct UsageParser {
    public static func parse(json: Data, now: Date = Date()) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        
        let response = try decoder.decode(UsageResponse.self, from: json)
        
        let fiveHourState = Self.convert(window: response.five_hour, now: now, kind: .fiveHour)
        let sevenDayState = Self.convert(window: response.seven_day, now: now, kind: .weekly)
        
        let group = UsageGroup(name: nil, windows: [fiveHourState, sevenDayState])
        return UsageSnapshot(groups: [group])
    }
    
    private static func convert(window: WindowUsage, now: Date, kind: WindowKind) -> UsageWindow {
        let percentRemaining = 100.0 - window.utilization
        
        let severity: Severity
        if window.utilization < 50.0 {
            severity = .green
        } else if window.utilization < 90.0 {
            severity = .yellow
        } else {
            severity = .red
        }
        
        let formatted: String
        guard let resetsAt = window.resets_at else {
            // No resets_at means this window hasn't started (0% utilization,
            // nothing sent in it yet) — matches Claude's own web UI copy for
            // this exact state ("Starts when a message is sent").
            return UsageWindow(
                kind: kind,
                percentRemaining: percentRemaining,
                severity: severity,
                resetsAtFormatted: "Starts when used",
                resetsAtAbsolute: nil,
                resetsAtDate: nil
            )
        }
        let timeRemaining = resetsAt.timeIntervalSince(now)
        if timeRemaining <= 0 {
            formatted = "0h 0m"
        } else {
            let hours = Int(timeRemaining) / 3600
            let minutes = (Int(timeRemaining) % 3600) / 60
            
            if hours > 24 {
                let days = hours / 24
                let remainingHours = hours % 24
                formatted = "\(days)d \(remainingHours)h"
            } else if hours > 0 {
                formatted = "\(hours)h \(minutes)m"
            } else {
                formatted = "\(minutes)m"
            }
        }
        
        return UsageWindow(
            kind: kind,
            percentRemaining: percentRemaining,
            severity: severity,
            resetsAtFormatted: formatted,
            resetsAtAbsolute: ResetTimeFormatter.absolute(resetsAt, now: now),
            resetsAtDate: resetsAt
        )
    }
}

fileprivate struct UsageResponse: Decodable {
    let five_hour: WindowUsage
    let seven_day: WindowUsage
}

fileprivate struct WindowUsage: Decodable {
    let utilization: Double
    // Claude's API sends `resets_at: null` when this window hasn't started yet
    // (0% utilization, no message sent in it — e.g. the 5-hour window before
    // you've sent anything). This is a legitimate, expected state, not an
    // error — must stay Optional, not force-decoded as Date.
    let resets_at: Date?
}
