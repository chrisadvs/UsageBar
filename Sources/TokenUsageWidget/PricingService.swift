import Foundation

public enum PricingParser {
    /// Parses pricing tables from HTML or Markdown content from Anthropic docs.
    public static func parse(content: String) -> [String: ModelPricing] {
        var results: [String: ModelPricing] = [:]

        // 1. Try parsing HTML table rows <tr>...</tr>. The real pricing page repeats the same
        // model names across several sections (standard "Model pricing", discounted "Batch
        // processing", unrelated "Tool use pricing" token-count tables, etc.) — scope to just
        // the "Model pricing" section so a later, differently-priced table (e.g. batch, which is
        // discounted) doesn't silently overwrite the standard price. Falls back to the full
        // content when no such heading is found, so simple test fixtures without section
        // headings still parse as before.
        let htmlScope = scopeToModelPricingSection(content) ?? content
        let htmlRows = extractHTMLRows(from: htmlScope)
        for row in htmlRows {
            if let (model, pricing) = parseRowCells(row) {
                results[model] = pricing
            }
        }

        // 2. Try parsing Markdown table lines | ... | ... | ... |
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { continue }
            let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            // Skip separator rows (e.g. |---|---|---|)
            if cells.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) }) {
                continue
            }
            if let (model, pricing) = parseCells(cells) {
                results[model] = pricing
            }
        }
        
        return results
    }
    
    private static func extractHTMLRows(from content: String) -> [[String]] {
        var rows: [[String]] = []
        let rowPattern = "(?is)<tr[^>]*>(.*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern) else { return [] }
        let cellPattern = "(?is)<t[dh][^>]*>(.*?)</t[dh]>"
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern) else { return [] }
        
        let nsContent = content as NSString
        let rowMatches = rowRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        
        for rowMatch in rowMatches {
            guard rowMatch.numberOfRanges > 1 else { continue }
            let rowContent = nsContent.substring(with: rowMatch.range(at: 1))
            let nsRow = rowContent as NSString
            let cellMatches = cellRegex.matches(in: rowContent, range: NSRange(location: 0, length: nsRow.length))
            
            var cells: [String] = []
            for cellMatch in cellMatches {
                guard cellMatch.numberOfRanges > 1 else { continue }
                var cellText = nsRow.substring(with: cellMatch.range(at: 1))
                // Strip nested tags
                cellText = cellText.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                cellText = cellText.trimmingCharacters(in: .whitespacesAndNewlines)
                cells.append(cellText)
            }
            if !cells.isEmpty {
                rows.append(cells)
            }
        }
        
        return rows
    }

    /// Slices `content` down to the section following a heading whose text contains "Model
    /// pricing", up to the next heading (any of h1–h4). Returns nil if no such heading exists,
    /// so callers can fall back to the full, unscoped content.
    private static func scopeToModelPricingSection(_ content: String) -> String? {
        let headingPattern = "(?is)<h[1-4][^>]*>(.*?)</h[1-4]>"
        guard let regex = try? NSRegularExpression(pattern: headingPattern) else { return nil }
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        var startLocation: Int?
        var endLocation = nsContent.length
        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges > 1 else { continue }
            var headingText = nsContent.substring(with: match.range(at: 1))
            headingText = headingText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if headingText.contains("Model pricing") {
                startLocation = match.range.location + match.range.length
                if index + 1 < matches.count {
                    endLocation = matches[index + 1].range.location
                }
                break
            }
        }

        guard let start = startLocation, start < endLocation else { return nil }
        return nsContent.substring(with: NSRange(location: start, length: endLocation - start))
    }

    private static func parseRowCells(_ cells: [String]) -> (String, ModelPricing)? {
        return parseCells(cells)
    }
    
    private static func parseCells(_ cells: [String]) -> (String, ModelPricing)? {
        guard cells.count >= 3 else { return nil }
        
        // Find model identifier
        var detectedModel: String?
        var modelCellIndex: Int?
        for (idx, cell) in cells.enumerated() {
            if let modelID = extractModelID(from: cell) {
                detectedModel = modelID
                modelCellIndex = idx
                break
            }
        }
        
        guard let model = detectedModel, let mIndex = modelCellIndex else { return nil }
        
        // Find dollar prices in remaining cells (excluding model cell)
        var prices: [Double] = []
        for (idx, cell) in cells.enumerated() {
            if idx == mIndex { continue }
            let extracted = extractPrices(from: cell)
            prices.append(contentsOf: extracted)
        }
        
        // We need at least input and output prices. Anthropic's live pricing page lists some
        // rows as just [input, output] and others as [input, 5m cache write, 1h cache write,
        // cache read, output] (confirmed against the real page's column headers: "Base Input
        // Tokens" first, "Output Tokens" last, with cache columns in between) — input is always
        // first and output is always last, regardless of how many cache columns sit between.
        guard prices.count >= 2 else { return nil }

        let inputPrice = prices[0]
        let outputPrice = prices[prices.count - 1]
        
        guard inputPrice > 0, outputPrice > 0 else { return nil }
        
        return (model, ModelPricing(inputPerMillion: inputPrice, outputPerMillion: outputPrice))
    }
    
    public static func extractModelID(from text: String) -> String? {
        // 1. Machine-readable slug (e.g. "claude-sonnet-5") — used by some docs/test fixtures.
        let slugPattern = "claude-[a-z0-9.-]+"
        if let regex = try? NSRegularExpression(pattern: slugPattern, options: .caseInsensitive) {
            let nsText = text as NSString
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range).lowercased()
                let cleaned = matched.trimmingCharacters(in: CharacterSet(charactersIn: ".-/ "))
                if cleaned.count >= 8 {
                    return cleaned
                }
            }
        }

        // 2. Human-readable display name (e.g. "Claude Sonnet 5", "Claude Opus 4.8") — this is
        // the actual format platform.claude.com/docs/en/about-claude/pricing uses in its table
        // cells, confirmed against the live page's raw HTML (no machine-readable slug appears
        // in the pricing rows themselves, only in unrelated anchor IDs). Normalize to a slug so
        // it matches the "claude-<family>-<version>[-<date>]" IDs found in real transcripts.
        let displayPattern = #"Claude\s+([A-Za-z]+)\s+([0-9]+(?:\.[0-9]+)?)"#
        if let regex = try? NSRegularExpression(pattern: displayPattern) {
            let nsText = text as NSString
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
               match.numberOfRanges >= 3 {
                let family = nsText.substring(with: match.range(at: 1)).lowercased()
                let version = nsText.substring(with: match.range(at: 2)).replacingOccurrences(of: ".", with: "-")
                return "claude-\(family)-\(version)"
            }
        }

        return nil
    }
    
    private static func extractPrices(from text: String) -> [Double] {
        // Pattern matches $2.00, $10, 2.00 / MTok, etc.
        let pattern = #"\$?\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        
        var results: [Double] = []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let numStr = nsText.substring(with: match.range(at: 1))
            if let val = Double(numStr) {
                // Only accept numbers that are actually in a dollar-price context ("$2", "$2 /
                // MTok"). Earlier this also accepted any cell containing the word "token" or a
                // bare "/", which was too loose: unrelated tables on the real pricing page reuse
                // the same model-name row labels for non-price data (e.g. a minimum-thinking-
                // budget table with cells like "354 tokens"), and those numbers were getting
                // parsed in as if they were dollar amounts.
                let matchStr = nsText.substring(with: match.range)
                if matchStr.contains("$") || text.lowercased().contains("mtok") {
                    results.append(val)
                }
            }
        }
        return results
    }
}

public enum CostCalculator {
    public static let cacheReadMultiplier = 0.1
    public static let cacheWrite5mMultiplier = 1.25
    public static let cacheWrite1hMultiplier = 2.0
    
    /// Finds matching model pricing in snapshot by exact match or normalized prefix.
    public static func matchPricing(for model: String, in pricingSnapshot: PricingSnapshot?) -> (modelKey: String, pricing: ModelPricing)? {
        guard let prices = pricingSnapshot?.prices, !prices.isEmpty else { return nil }
        
        let lowerModel = model.lowercased()
        
        // 1. Exact match
        if let direct = prices[lowerModel] {
            return (lowerModel, direct)
        }
        
        // 2. Strip date suffix (e.g. claude-haiku-4-5-20251001 -> claude-haiku-4-5)
        let stripped = lowerModel.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        if let directStripped = prices[stripped] {
            return (stripped, directStripped)
        }
        
        // 3. Prefix matching against known keys (pick longest matching key)
        var bestMatch: (String, ModelPricing)?
        for (key, pricing) in prices {
            let lowerKey = key.lowercased()
            if lowerModel.hasPrefix(lowerKey) || stripped.hasPrefix(lowerKey) {
                if bestMatch == nil || lowerKey.count > bestMatch!.0.count {
                    bestMatch = (key, pricing)
                }
            }
        }
        
        return bestMatch
    }
    
    /// Calculates USD cost for given counts and pricing.
    public static func calculateCost(counts: TokenCounts, pricing: ModelPricing) -> Double {
        let inputCost = (Double(counts.input) / 1_000_000.0) * pricing.inputPerMillion
        let outputCost = (Double(counts.output) / 1_000_000.0) * pricing.outputPerMillion
        let cacheReadCost = (Double(counts.cacheRead) / 1_000_000.0) * (pricing.inputPerMillion * cacheReadMultiplier)
        let cacheWrite5mCost = (Double(counts.cacheCreation5m) / 1_000_000.0) * (pricing.inputPerMillion * cacheWrite5mMultiplier)
        let cacheWrite1hCost = (Double(counts.cacheCreation1h) / 1_000_000.0) * (pricing.inputPerMillion * cacheWrite1hMultiplier)
        
        return inputCost + outputCost + cacheReadCost + cacheWrite5mCost + cacheWrite1hCost
    }
}

public actor PricingService {
    public static let shared = PricingService()
    public static let pricingEndpoint = URL(string: "https://platform.claude.com/docs/en/about-claude/pricing")!
    
    private var session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func fetchPricing(currentSnapshot: PricingSnapshot?, force: Bool = false, now: Date = Date()) async -> PricingSnapshot? {
        if !force, let current = currentSnapshot {
            let age = now.timeIntervalSince(current.lastFetchedAt)
            if age < 86400 { // 24 hours
                return current
            }
        }
        
        AppLogger.shared.log("[PricingService] Fetching pricing from \(Self.pricingEndpoint)...", level: .info)
        
        var request = URLRequest(url: Self.pricingEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                AppLogger.shared.log("[PricingService] Pricing fetch HTTP error: \(status)", level: .warn)
                return currentSnapshot
            }
            
            guard let htmlString = String(data: data, encoding: .utf8) else {
                AppLogger.shared.log("[PricingService] Failed to decode pricing response body", level: .warn)
                return currentSnapshot
            }
            
            let parsed = PricingParser.parse(content: htmlString)
            if !parsed.isEmpty {
                AppLogger.shared.log("[PricingService] Successfully parsed \(parsed.count) model pricing entries", level: .info)
                return PricingSnapshot(lastFetchedAt: now, prices: parsed)
            } else {
                AppLogger.shared.log("[PricingService] No pricing entries found in page content", level: .warn)
                return currentSnapshot
            }
        } catch {
            AppLogger.shared.log("[PricingService] Network error fetching pricing: \(error.localizedDescription)", level: .warn)
            return currentSnapshot
        }
    }
}
