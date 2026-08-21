import Foundation

public enum TranscriptParser {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let dateStr = try container.decode(String.self)
            if let date = dateFormatter.date(from: dateStr) {
                return date
            }
            if let date = fallbackDateFormatter.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date string: \(dateStr)")
        }
        return decoder
    }
    
    public static func parseLine(data: Data, filePath: String, lineNumber: Int, decoder: JSONDecoder? = nil) -> TokenUsageRecord? {
        guard !data.isEmpty else { return nil }
        
        let jsonDecoder = decoder ?? makeDecoder()
        
        do {
            let line = try jsonDecoder.decode(TranscriptLine.self, from: data)
            guard line.type == "assistant" else { return nil }
            guard let msg = line.message, let model = msg.model, model != "<synthetic>" else {
                return nil
            }
            guard let messageID = msg.id, !messageID.isEmpty else {
                return nil
            }
            guard let timestamp = line.timestamp else {
                return nil
            }
            
            let usage = msg.usage
            let input = usage?.input_tokens ?? 0
            let output = usage?.output_tokens ?? 0
            let cacheRead = usage?.cache_read_input_tokens ?? 0
            
            let cache5m: Int
            let cache1h: Int
            if let creation = usage?.cache_creation {
                cache5m = creation.ephemeral_5m_input_tokens ?? 0
                cache1h = creation.ephemeral_1h_input_tokens ?? 0
            } else {
                cache5m = usage?.cache_creation_input_tokens ?? 0
                cache1h = 0
            }
            
            let counts = TokenCounts(
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheCreation5m: cache5m,
                cacheCreation1h: cache1h
            )
            
            return TokenUsageRecord(
                messageID: messageID,
                timestamp: timestamp,
                model: model,
                counts: counts
            )
        } catch {
            let fileName = (filePath as NSString).lastPathComponent
            AppLogger.shared.log("[TranscriptParser] JSON decode error in \(fileName):\(lineNumber) [\(type(of: error))]", level: .warn)
            return nil
        }
    }
}

fileprivate struct TranscriptLine: Decodable {
    let type: String?
    let timestamp: Date?
    let message: TranscriptMessage?
}

fileprivate struct TranscriptMessage: Decodable {
    let id: String?
    let model: String?
    let usage: TranscriptUsage?
}

fileprivate struct TranscriptUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_creation: TranscriptCacheCreation?
}

fileprivate struct TranscriptCacheCreation: Decodable {
    let ephemeral_5m_input_tokens: Int?
    let ephemeral_1h_input_tokens: Int?
}
