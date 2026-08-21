import Foundation

public struct TokenCounts: Codable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheCreation5m: Int
    public var cacheCreation1h: Int

    public var cacheCreationTotal: Int {
        cacheCreation5m + cacheCreation1h
    }

    public var total: Int {
        input + output + cacheRead + cacheCreationTotal
    }

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation5m: Int = 0,
        cacheCreation1h: Int = 0
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation5m = cacheCreation5m
        self.cacheCreation1h = cacheCreation1h
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheCreation5m: lhs.cacheCreation5m + rhs.cacheCreation5m,
            cacheCreation1h: lhs.cacheCreation1h + rhs.cacheCreation1h
        )
    }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs = lhs + rhs
    }
}

public struct TokenUsageRecord: Codable, Equatable {
    public let messageID: String
    public let timestamp: Date
    public let model: String
    public let counts: TokenCounts

    public init(messageID: String, timestamp: Date, model: String, counts: TokenCounts) {
        self.messageID = messageID
        self.timestamp = timestamp
        self.model = model
        self.counts = counts
    }
}

public struct DailyModelBucket: Codable, Equatable {
    public let day: Date // Calendar.current.startOfDay, local time zone
    public let model: String
    public var counts: TokenCounts
    public var messageCount: Int

    public init(day: Date, model: String, counts: TokenCounts, messageCount: Int) {
        self.day = day
        self.model = model
        self.counts = counts
        self.messageCount = messageCount
    }
}

public struct TrendBucket: Codable, Equatable, Identifiable {
    public let bucketStart: Date
    public let model: String
    public var counts: TokenCounts
    public var messageCount: Int

    public var id: String {
        "\(bucketStart.timeIntervalSince1970)_\(model)"
    }

    public init(bucketStart: Date, model: String, counts: TokenCounts, messageCount: Int = 1) {
        self.bucketStart = bucketStart
        self.model = model
        self.counts = counts
        self.messageCount = messageCount
    }
}

public enum TokenUsageScope: String, CaseIterable, Identifiable, Codable {
    case currentFiveHourWindow
    case today
    case thisWeek
    case thisMonth

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .currentFiveHourWindow:
            return "5-Hour Window"
        case .today:
            return "Today"
        case .thisWeek:
            return "This Week"
        case .thisMonth:
            return "This Month"
        }
    }
}

public struct TokenUsageSummary: Equatable {
    public let scope: TokenUsageScope
    public let counts: TokenCounts
    public let perModel: [String: TokenCounts]
    public let estimatedCostUSD: Double? // nil = scope contains only unknown models or pricing unavailable
    public let unpricedMessageCount: Int // messages using unknown models not counted in cost estimate
    public let isPartial: Bool // initial indexing in progress

    public init(
        scope: TokenUsageScope,
        counts: TokenCounts,
        perModel: [String: TokenCounts],
        estimatedCostUSD: Double?,
        unpricedMessageCount: Int,
        isPartial: Bool
    ) {
        self.scope = scope
        self.counts = counts
        self.perModel = perModel
        self.estimatedCostUSD = estimatedCostUSD
        self.unpricedMessageCount = unpricedMessageCount
        self.isPartial = isPartial
    }
}

public struct FileIndexEntry: Codable, Equatable {
    public let path: String
    public let byteSize: Int64
    public let modifiedAt: Date
    public let scannedByteOffset: Int64
    public let aggregated: [DailyModelBucket]

    public init(
        path: String,
        byteSize: Int64,
        modifiedAt: Date,
        scannedByteOffset: Int64,
        aggregated: [DailyModelBucket]
    ) {
        self.path = path
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.scannedByteOffset = scannedByteOffset
        self.aggregated = aggregated
    }
}

public struct ModelPricing: Codable, Equatable {
    public let inputPerMillion: Double
    public let outputPerMillion: Double

    public init(inputPerMillion: Double, outputPerMillion: Double) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
    }
}

public struct PricingSnapshot: Codable, Equatable {
    public let lastFetchedAt: Date
    public let prices: [String: ModelPricing]

    public init(lastFetchedAt: Date, prices: [String: ModelPricing]) {
        self.lastFetchedAt = lastFetchedAt
        self.prices = prices
    }
}

public struct TokenStatsSnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let lastScanAt: Date
    public let fileIndex: [FileIndexEntry]
    public let recentRecords: [TokenUsageRecord]
    public let pricing: PricingSnapshot?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        lastScanAt: Date,
        fileIndex: [FileIndexEntry],
        recentRecords: [TokenUsageRecord],
        pricing: PricingSnapshot?
    ) {
        self.schemaVersion = schemaVersion
        self.lastScanAt = lastScanAt
        self.fileIndex = fileIndex
        self.recentRecords = recentRecords
        self.pricing = pricing
    }
}

public enum TokenFormatter {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    public static func formatCompact(_ count: Int) -> String {
        let doubleCount = Double(count)
        if count >= 1_000_000_000 {
            return String(format: "%.2fB", doubleCount / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM", doubleCount / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", doubleCount / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    public static func formatNumber(_ count: Int) -> String {
        return numberFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    public static func formatUSD(_ amount: Double?) -> String {
        guard let amount = amount else { return "—" }
        if amount == 0 {
            return "$0.00"
        } else if amount < 0.01 {
            return String(format: "$%.3f", amount)
        } else {
            return String(format: "$%.2f", amount)
        }
    }
}
