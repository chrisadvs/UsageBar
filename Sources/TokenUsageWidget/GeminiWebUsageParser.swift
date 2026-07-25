import Foundation

public enum GeminiWebUsageParser {
    public enum ParseError: Error {
        case invalidFormat
        case missingTargetBlock
        case invalidInnerJSON
    }

    public static func parse(string: String, now: Date = Date()) throws -> UsageSnapshot {
        let jsonStr = try extractInnerJSON(from: string)
        return try parseInnerJSON(jsonString: jsonStr, now: now)
    }

    public static func extractInnerJSON(from string: String) throws -> String {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(")]}'") {
            text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var currentIndex = text.startIndex
        while currentIndex < text.endIndex {
            guard let newlineIndex = text[currentIndex...].firstIndex(of: "\n") else { break }
            let lengthString = String(text[currentIndex..<newlineIndex]).trimmingCharacters(in: .whitespaces)
            
            guard let length = Int(lengthString) else { break }
            
            let jsonStartIndex = text.index(after: newlineIndex)
            let jsonEndIndex = text.index(jsonStartIndex, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
            
            let chunk = String(text[jsonStartIndex..<jsonEndIndex])
            
            if let inner = tryExtractTarget(fromChunk: chunk) {
                return inner
            }
            
            currentIndex = jsonEndIndex
            while currentIndex < text.endIndex && text[currentIndex].isNewline {
                currentIndex = text.index(after: currentIndex)
            }
        }
        
        if let inner = tryExtractTarget(fromChunk: text) {
            return inner
        }
        
        throw ParseError.missingTargetBlock
    }
    
    private static func tryExtractTarget(fromChunk chunk: String) -> String? {
        var cleanChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstBracket = cleanChunk.firstIndex(of: "["),
           let lastBracket = cleanChunk.lastIndex(of: "]") {
            cleanChunk = String(cleanChunk[firstBracket...lastBracket])
        } else {
            return nil
        }
        
        guard let data = cleanChunk.data(using: .utf8) else { return nil }
        guard let outerObj = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        
        if let arr = outerObj as? [[Any]] {
            for item in arr {
                if let innerArr = item as? [Any], innerArr.count > 2, let id = innerArr[1] as? String, id == "jSf9Qc", let inner = innerArr[2] as? String {
                    return inner
                }
            }
        }
        
        if let arr = outerObj as? [[[Any]]] {
            for subArr in arr {
                for item in subArr {
                    if item.count > 2, let id = item[1] as? String, id == "jSf9Qc", let inner = item[2] as? String {
                        return inner
                    }
                }
            }
        }
        
        return nil
    }

    public static func parseInnerJSON(jsonString: String, now: Date) throws -> UsageSnapshot {
        guard let data = jsonString.data(using: .utf8),
              let rootArray = try JSONSerialization.jsonObject(with: data, options: []) as? [Any],
              rootArray.count >= 2,
              let limitsArray = rootArray[1] as? [[Any]] else {
            throw ParseError.invalidInnerJSON
        }
        
        var windows: [UsageWindow] = []
        
        for limitItem in limitsArray {
            guard limitItem.count >= 4,
                  let usedFraction = limitItem[1] as? Double,
                  let ordinal = limitItem[2] as? Int,
                  let nestedArray = limitItem[3] as? [[Any]],
                  let firstNested = nestedArray.first,
                  firstNested.count >= 1,
                  let resetUnix = firstNested[0] as? Double else {
                continue
            }
            
            let kind: WindowKind = ordinal == 1 ? .fiveHour : .weekly
            let percentRemaining = (1.0 - usedFraction) * 100.0
            
            let severity: Severity
            if percentRemaining > 50.0 {
                severity = .green
            } else if percentRemaining > 10.0 {
                severity = .yellow
            } else {
                severity = .red
            }
            
            let resetDate = Date(timeIntervalSince1970: resetUnix)
            let timeRemaining = resetDate.timeIntervalSince(now)
            
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
        
        windows.sort { $0.kind == .fiveHour && $1.kind == .weekly }
        
        let group = UsageGroup(name: nil, windows: windows)
        return UsageSnapshot(groups: [group])
    }
}
