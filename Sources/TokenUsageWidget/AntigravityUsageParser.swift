import Foundation

public struct AntigravityUsageParser {
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
        
        let response = try decoder.decode(AntigravityResponse.self, from: json)
        
        var usageGroups: [UsageGroup] = []
        for group in response.groups {
            var windows: [UsageWindow] = []
            for bucket in group.buckets {
                let kind: WindowKind = (bucket.window == "5h") ? .fiveHour : .weekly
                let percentRemaining = bucket.remainingFraction * 100.0
                
                let severity: Severity
                if percentRemaining > 50.0 {
                    severity = .green
                } else if percentRemaining > 10.0 {
                    severity = .yellow
                } else {
                    severity = .red
                }
                
                let timeRemaining = bucket.resetTime.timeIntervalSince(now)
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
                
                windows.append(UsageWindow(
                    kind: kind,
                    percentRemaining: percentRemaining,
                    severity: severity,
                    resetsAtFormatted: formatted
                ))
            }
            
            // Sort windows so 5h is first, weekly is second (for UI consistency)
            windows.sort { $0.kind == .fiveHour && $1.kind == .weekly }
            
            usageGroups.append(UsageGroup(name: group.displayName, windows: windows))
        }
        
        return UsageSnapshot(groups: usageGroups)
    }
}

fileprivate struct AntigravityResponse: Decodable {
    let groups: [AntigravityGroup]
}

fileprivate struct AntigravityGroup: Decodable {
    let displayName: String?
    let buckets: [AntigravityBucket]
}

fileprivate struct AntigravityBucket: Decodable {
    let window: String
    let resetTime: Date
    let remainingFraction: Double
}
