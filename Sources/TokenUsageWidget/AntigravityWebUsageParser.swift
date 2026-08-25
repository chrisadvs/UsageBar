import Foundation

public enum AntigravityWebUsageParser {
    public enum ParseError: Error, LocalizedError {
        case invalidData
        case missingResponse
        
        public var errorDescription: String? {
            switch self {
            case .invalidData:
                return "Invalid response data for Antigravity."
            case .missingResponse:
                return "Missing response groups in Antigravity quota payload."
            }
        }
    }
    
    private struct QuotaPayload: Decodable {
        let response: QuotaResponseBody
    }
    
    private struct QuotaResponseBody: Decodable {
        let groups: [QuotaGroupPayload]?
    }
    
    private struct QuotaGroupPayload: Decodable {
        let displayName: String?
        let buckets: [QuotaBucketPayload]?
    }
    
    private struct QuotaBucketPayload: Decodable {
        let bucketId: String?
        let displayName: String?
        let window: String?
        let remainingFraction: Double?
        let resetTime: String?
    }
    
    public static func parse(string: String, now: Date = Date()) throws -> UsageSnapshot {
        guard let data = string.data(using: .utf8) else {
            throw ParseError.invalidData
        }
        return try parse(data: data, now: now)
    }
    
    public static func parse(data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let payload = try? JSONDecoder().decode(QuotaPayload.self, from: data) else {
            throw ParseError.invalidData
        }
        let responseBody = payload.response

        guard let rawGroups = responseBody.groups, !rawGroups.isEmpty else {
            throw ParseError.missingResponse
        }
        
        var usageGroups: [UsageGroup] = []
        
        for rawGroup in rawGroups {
            var windows: [UsageWindow] = []
            
            for bucket in rawGroup.buckets ?? [] {
                guard let windowStr = bucket.window else { continue }
                
                let kind: WindowKind
                if windowStr == "5h" {
                    kind = .fiveHour
                } else if windowStr == "weekly" {
                    kind = .weekly
                } else {
                    continue
                }
                
                let fraction = bucket.remainingFraction ?? 0.0
                let percentRemaining = fraction * 100.0
                
                let severity: Severity
                if percentRemaining > 50.0 {
                    severity = .green
                } else if percentRemaining > 10.0 {
                    severity = .yellow
                } else {
                    severity = .red
                }
                
                var resetDate: Date? = nil
                if let resetTimeStr = bucket.resetTime {
                    resetDate = parseISO8601Date(resetTimeStr)
                }
                
                let formatted: String
                let absolute: String?
                
                if let resetDate = resetDate {
                    let timeRemaining = resetDate.timeIntervalSince(now)
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
                    absolute = ResetTimeFormatter.absolute(resetDate, now: now)
                } else {
                    formatted = ""
                    absolute = nil
                }
                
                windows.append(UsageWindow(
                    kind: kind,
                    percentRemaining: percentRemaining,
                    severity: severity,
                    resetsAtFormatted: formatted,
                    resetsAtAbsolute: absolute,
                    resetsAtDate: resetDate
                ))
            }
            
            windows.sort { $0.kind.sortOrder < $1.kind.sortOrder }
            usageGroups.append(UsageGroup(name: rawGroup.displayName, windows: windows))
        }
        
        return UsageSnapshot(groups: usageGroups)
    }
    
    private static func parseISO8601Date(_ dateString: String) -> Date? {
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFraction.date(from: dateString) {
            return date
        }
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: dateString)
    }
}
