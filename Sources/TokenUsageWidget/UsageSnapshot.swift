import Foundation

public struct WindowState: Equatable {
    public let percentRemaining: Double
    public let severity: Severity
    public let resetsAtFormatted: String
    
    public init(percentRemaining: Double, severity: Severity, resetsAtFormatted: String) {
        self.percentRemaining = percentRemaining
        self.severity = severity
        self.resetsAtFormatted = resetsAtFormatted
    }
}

public enum Severity: Equatable {
    case green, yellow, red
}

public struct UsageSnapshot: Equatable {
    public let fiveHour: WindowState
    public let sevenDay: WindowState
    
    public init(fiveHour: WindowState, sevenDay: WindowState) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
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
        
        let fiveHourState = Self.convert(window: response.five_hour, now: now)
        let sevenDayState = Self.convert(window: response.seven_day, now: now)
        
        return UsageSnapshot(fiveHour: fiveHourState, sevenDay: sevenDayState)
    }
    
    private static func convert(window: WindowUsage, now: Date) -> WindowState {
        let percentRemaining = 100.0 - window.utilization
        
        let severity: Severity
        if window.utilization < 50.0 {
            severity = .green
        } else if window.utilization < 90.0 {
            severity = .yellow
        } else {
            severity = .red
        }
        
        let timeRemaining = window.resets_at.timeIntervalSince(now)
        let formatted: String
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
        
        return WindowState(
            percentRemaining: percentRemaining,
            severity: severity,
            resetsAtFormatted: formatted
        )
    }
}

fileprivate struct UsageResponse: Decodable {
    let five_hour: WindowUsage
    let seven_day: WindowUsage
}

fileprivate struct WindowUsage: Decodable {
    let utilization: Double
    let resets_at: Date
}
