import Foundation

public actor TokenUsageStore {
    public static let shared = TokenUsageStore()
    
    public static var defaultTranscriptsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }
    
    public static var defaultStorageFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "TokenUsageWidget"
        let dir = appSupport.appendingPathComponent(bundleID)
        return dir.appendingPathComponent("token-stats.json")
    }
    
    private let transcriptsDirectory: URL
    private let storageFileURL: URL
    private let pricingService: PricingService
    
    private var fileIndex: [String: FileIndexEntry]
    private var recentRecords: [TokenUsageRecord]
    private var pricingSnapshot: PricingSnapshot?
    private var isInitialIndexing: Bool
    private var lastScanAt: Date?

    public init(
        transcriptsDirectory: URL = TokenUsageStore.defaultTranscriptsDirectory,
        storageFileURL: URL = TokenUsageStore.defaultStorageFileURL,
        pricingService: PricingService = .shared,
        initialPricing: PricingSnapshot? = nil
    ) {
        self.transcriptsDirectory = transcriptsDirectory
        self.storageFileURL = storageFileURL
        self.pricingService = pricingService

        if let data = Self.loadSnapshotData(from: storageFileURL) {
            self.fileIndex = data.fileIndex
            self.recentRecords = data.recentRecords
            self.lastScanAt = data.lastScanAt
            self.isInitialIndexing = false
            self.pricingSnapshot = data.pricingSnapshot ?? initialPricing
        } else {
            self.fileIndex = [:]
            self.recentRecords = []
            self.lastScanAt = nil
            self.isInitialIndexing = true
            self.pricingSnapshot = initialPricing
        }
    }
    
    // MARK: - Persistence
    
    private static func loadSnapshotData(from url: URL) -> (fileIndex: [String: FileIndexEntry], recentRecords: [TokenUsageRecord], pricingSnapshot: PricingSnapshot?, lastScanAt: Date?)? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let snapshot = try decoder.decode(TokenStatsSnapshot.self, from: data)
            
            guard snapshot.schemaVersion == TokenStatsSnapshot.currentSchemaVersion else {
                AppLogger.shared.log("[TokenUsageStore] Schema version mismatch (found \(snapshot.schemaVersion), expected \(TokenStatsSnapshot.currentSchemaVersion)). Discarding cache.", level: .warn)
                return nil
            }
            
            var indexMap: [String: FileIndexEntry] = [:]
            for entry in snapshot.fileIndex {
                indexMap[entry.path] = entry
            }
            
            AppLogger.shared.log("[TokenUsageStore] Loaded snapshot with \(indexMap.count) files and \(snapshot.recentRecords.count) recent records.", level: .info)
            return (indexMap, snapshot.recentRecords, snapshot.pricing, snapshot.lastScanAt)
        } catch {
            AppLogger.shared.log("[TokenUsageStore] Failed to load snapshot: \(error.localizedDescription). Rebuilding index.", level: .warn)
            return nil
        }
    }
    
    private func saveSnapshot(now: Date = Date()) {
        let dir = storageFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        let cutoff48h = now.addingTimeInterval(-48 * 3600)
        let prunedRecent = recentRecords.filter { $0.timestamp >= cutoff48h }
        self.recentRecords = prunedRecent
        
        let snapshot = TokenStatsSnapshot(
            schemaVersion: TokenStatsSnapshot.currentSchemaVersion,
            lastScanAt: now,
            fileIndex: Array(fileIndex.values),
            recentRecords: prunedRecent,
            pricing: pricingSnapshot
        )
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshot)
            try data.write(to: storageFileURL, options: .atomic)
            self.lastScanAt = now
        } catch {
            AppLogger.shared.log("[TokenUsageStore] Failed to persist token-stats.json: \(error.localizedDescription)", level: .error)
        }
    }
    
    // MARK: - Scanning & Indexing
    
    public func refresh(
        fiveHourWindowStart: Date?,
        now: Date = Date(),
        forcePricingRefresh: Bool = false
    ) async -> [TokenUsageScope: TokenUsageSummary] {
        let startTime = Date()
        
        // 1. Update pricing if needed
        self.pricingSnapshot = await pricingService.fetchPricing(
            currentSnapshot: self.pricingSnapshot,
            force: forcePricingRefresh,
            now: now
        )
        
        // 2. Scan transcripts directory
        await scanTranscripts(now: now)
        
        self.isInitialIndexing = false
        saveSnapshot(now: now)
        
        let duration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log("[TokenUsageStore] Refresh complete in \(String(format: "%.2f", duration))s. Total indexed files: \(fileIndex.count).", level: .info)
        
        // 3. Compute summaries for all scopes
        return computeSummaries(fiveHourWindowStart: fiveHourWindowStart, now: now)
    }
    
    private func scanTranscripts(now: Date) async {
        guard FileManager.default.fileExists(atPath: transcriptsDirectory.path) else {
            return
        }
        
        let jsonlFiles = findJSONLFiles(in: transcriptsDirectory)
        var currentPaths = Set<String>()
        let cutoff48h = now.addingTimeInterval(-48 * 3600)
        
        for fileURL in jsonlFiles {
            let path = fileURL.path
            currentPaths.insert(path)
            
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let fileSize = values.fileSize,
                  let modDate = values.contentModificationDate else {
                continue
            }
            
            let int64Size = Int64(fileSize)
            
            if let existing = fileIndex[path] {
                // Check if unchanged
                if existing.byteSize == int64Size && abs(existing.modifiedAt.timeIntervalSince(modDate)) < 1.0 {
                    // Unchanged: skip file opening
                    continue
                } else if int64Size > existing.byteSize && existing.scannedByteOffset > 0 {
                    // Incremental scan
                    scanIncremental(fileURL: fileURL, existing: existing, currentSize: int64Size, modDate: modDate, cutoff48h: cutoff48h)
                } else {
                    // Size decreased or modified date changed without size increase -> full rescan
                    scanFull(fileURL: fileURL, size: int64Size, modDate: modDate, cutoff48h: cutoff48h)
                }
            } else {
                // New file -> full scan
                scanFull(fileURL: fileURL, size: int64Size, modDate: modDate, cutoff48h: cutoff48h)
            }
        }
        
        // Clean up removed files
        let removedKeys = fileIndex.keys.filter { !currentPaths.contains($0) }
        for key in removedKeys {
            fileIndex.removeValue(forKey: key)
        }
    }
    
    private func scanFull(fileURL: URL, size: Int64, modDate: Date, cutoff48h: Date) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        
        let data = handle.readDataToEndOfFile()
        let path = fileURL.path
        
        var seenMessageIDs = Set<String>()
        var bucketsMap: [String: DailyModelBucket] = [:] // key: "\(dayUnix)_\(model)"
        var newRecentRecords: [TokenUsageRecord] = []
        
        // Find last newline index
        guard let lastNewlineIndex = data.lastIndex(of: 0x0A) else {
            // No full lines yet
            fileIndex[path] = FileIndexEntry(path: path, byteSize: size, modifiedAt: modDate, scannedByteOffset: 0, aggregated: [])
            return
        }
        
        let scannedOffset = Int64(lastNewlineIndex + 1)
        let parseData = data.prefix(upTo: lastNewlineIndex + 1)
        let decoder = TranscriptParser.makeDecoder()
        
        var lineStart = parseData.startIndex
        var lineNumber = 1
        
        while lineStart < parseData.endIndex {
            guard let nextNewline = parseData[lineStart...].firstIndex(of: 0x0A) else { break }
            let lineBytes = parseData[lineStart..<nextNewline]
            lineStart = parseData.index(after: nextNewline)
            
            if let record = TranscriptParser.parseLine(data: lineBytes, filePath: path, lineNumber: lineNumber, decoder: decoder) {
                // Deduplicate within file by messageID
                if !seenMessageIDs.contains(record.messageID) {
                    seenMessageIDs.insert(record.messageID)
                    
                    let startOfDay = Calendar.current.startOfDay(for: record.timestamp)
                    let bucketKey = "\(startOfDay.timeIntervalSince1970)_\(record.model)"
                    if var existingBucket = bucketsMap[bucketKey] {
                        existingBucket.counts += record.counts
                        existingBucket.messageCount += 1
                        bucketsMap[bucketKey] = existingBucket
                    } else {
                        bucketsMap[bucketKey] = DailyModelBucket(
                            day: startOfDay,
                            model: record.model,
                            counts: record.counts,
                            messageCount: 1
                        )
                    }
                    
                    if record.timestamp >= cutoff48h {
                        newRecentRecords.append(record)
                    }
                }
            }
            lineNumber += 1
        }
        
        let aggregated = Array(bucketsMap.values)
        fileIndex[path] = FileIndexEntry(
            path: path,
            byteSize: size,
            modifiedAt: modDate,
            scannedByteOffset: scannedOffset,
            aggregated: aggregated
        )
        
        // Update recent records
        for record in newRecentRecords {
            if !recentRecords.contains(where: { $0.messageID == record.messageID }) {
                recentRecords.append(record)
            }
        }
    }
    
    private func scanIncremental(fileURL: URL, existing: FileIndexEntry, currentSize: Int64, modDate: Date, cutoff48h: Date) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        
        do {
            try handle.seek(toOffset: UInt64(existing.scannedByteOffset))
        } catch {
            scanFull(fileURL: fileURL, size: currentSize, modDate: modDate, cutoff48h: cutoff48h)
            return
        }
        
        let data = handle.readDataToEndOfFile()
        guard let lastNewlineIndex = data.lastIndex(of: 0x0A) else {
            // No new full line added yet
            fileIndex[fileURL.path] = FileIndexEntry(
                path: existing.path,
                byteSize: currentSize,
                modifiedAt: modDate,
                scannedByteOffset: existing.scannedByteOffset,
                aggregated: existing.aggregated
            )
            return
        }
        
        let newScannedOffset = existing.scannedByteOffset + Int64(lastNewlineIndex + 1)
        let parseData = data.prefix(upTo: lastNewlineIndex + 1)
        let decoder = TranscriptParser.makeDecoder()
        
        var bucketsMap: [String: DailyModelBucket] = [:]
        for b in existing.aggregated {
            let key = "\(b.day.timeIntervalSince1970)_\(b.model)"
            bucketsMap[key] = b
        }
        
        var lineStart = parseData.startIndex
        var lineNumber = 1
        var newRecent: [TokenUsageRecord] = []
        // Dedup against the 48h rolling buffer: a message straddling the
        // previous scan's offset boundary (half already aggregated, half
        // arriving in this increment) must not be double-counted. recentRecords
        // covers the full window a streaming message could span.
        var seenMessageIDs = Set(recentRecords.map { $0.messageID })

        while lineStart < parseData.endIndex {
            guard let nextNewline = parseData[lineStart...].firstIndex(of: 0x0A) else { break }
            let lineBytes = parseData[lineStart..<nextNewline]
            lineStart = parseData.index(after: nextNewline)

            if let record = TranscriptParser.parseLine(data: lineBytes, filePath: fileURL.path, lineNumber: lineNumber, decoder: decoder) {
                guard !seenMessageIDs.contains(record.messageID) else {
                    lineNumber += 1
                    continue
                }
                seenMessageIDs.insert(record.messageID)

                // Note: incremental parse appends to existing buckets
                let startOfDay = Calendar.current.startOfDay(for: record.timestamp)
                let bucketKey = "\(startOfDay.timeIntervalSince1970)_\(record.model)"
                if var existingBucket = bucketsMap[bucketKey] {
                    existingBucket.counts += record.counts
                    existingBucket.messageCount += 1
                    bucketsMap[bucketKey] = existingBucket
                } else {
                    bucketsMap[bucketKey] = DailyModelBucket(
                        day: startOfDay,
                        model: record.model,
                        counts: record.counts,
                        messageCount: 1
                    )
                }

                if record.timestamp >= cutoff48h {
                    newRecent.append(record)
                }
            }
            lineNumber += 1
        }
        
        fileIndex[fileURL.path] = FileIndexEntry(
            path: existing.path,
            byteSize: currentSize,
            modifiedAt: modDate,
            scannedByteOffset: newScannedOffset,
            aggregated: Array(bucketsMap.values)
        )
        
        for record in newRecent {
            if !recentRecords.contains(where: { $0.messageID == record.messageID }) {
                recentRecords.append(record)
            }
        }
    }
    
    private func findJSONLFiles(in directory: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "jsonl" {
                results.append(fileURL)
            }
        }
        return results
    }
    
    // MARK: - Summary Computation
    
    public func computeSummaries(fiveHourWindowStart: Date?, now: Date = Date()) -> [TokenUsageScope: TokenUsageSummary] {
        var summaries: [TokenUsageScope: TokenUsageSummary] = [:]
        
        // 1. Current 5-Hour Window
        if let windowStart = fiveHourWindowStart {
            let matchingRecords = recentRecords.filter { $0.timestamp >= windowStart && $0.timestamp <= now }
            var totalCounts = TokenCounts()
            var perModel: [String: TokenCounts] = [:]
            var modelMessageCounts: [String: Int] = [:]
            
            for record in matchingRecords {
                totalCounts += record.counts
                perModel[record.model, default: TokenCounts()] += record.counts
                modelMessageCounts[record.model, default: 0] += 1
            }
            
            let (estimatedCost, unpricedCount) = calculateCostAndUnpriced(
                perModel: perModel,
                modelMessageCounts: modelMessageCounts
            )
            
            summaries[.currentFiveHourWindow] = TokenUsageSummary(
                scope: .currentFiveHourWindow,
                counts: totalCounts,
                perModel: perModel,
                estimatedCostUSD: estimatedCost,
                unpricedMessageCount: unpricedCount,
                isPartial: isInitialIndexing
            )
        } else {
            summaries[.currentFiveHourWindow] = TokenUsageSummary(
                scope: .currentFiveHourWindow,
                counts: TokenCounts(),
                perModel: [:],
                estimatedCostUSD: nil,
                unpricedMessageCount: 0,
                isPartial: isInitialIndexing
            )
        }
        
        // 2. Today
        let startOfToday = Calendar.current.startOfDay(for: now)
        summaries[.today] = aggregateScope(
            scope: .today,
            filter: { $0.day == startOfToday }
        )
        
        // 3. This Week
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        summaries[.thisWeek] = aggregateScope(
            scope: .thisWeek,
            filter: { $0.day >= startOfWeek && $0.day <= now }
        )
        
        // 4. This Month
        let startOfMonth = Calendar.current.dateInterval(of: .month, for: now)?.start ?? startOfToday
        summaries[.thisMonth] = aggregateScope(
            scope: .thisMonth,
            filter: { $0.day >= startOfMonth && $0.day <= now }
        )
        
        return summaries
    }
    
    private func aggregateScope(
        scope: TokenUsageScope,
        filter: (DailyModelBucket) -> Bool
    ) -> TokenUsageSummary {
        var totalCounts = TokenCounts()
        var perModel: [String: TokenCounts] = [:]
        var modelMessageCounts: [String: Int] = [:]
        
        for entry in fileIndex.values {
            for bucket in entry.aggregated {
                if filter(bucket) {
                    totalCounts += bucket.counts
                    perModel[bucket.model, default: TokenCounts()] += bucket.counts
                    modelMessageCounts[bucket.model, default: 0] += bucket.messageCount
                }
            }
        }
        
        let (estimatedCost, unpricedCount) = calculateCostAndUnpriced(
            perModel: perModel,
            modelMessageCounts: modelMessageCounts
        )
        
        return TokenUsageSummary(
            scope: scope,
            counts: totalCounts,
            perModel: perModel,
            estimatedCostUSD: estimatedCost,
            unpricedMessageCount: unpricedCount,
            isPartial: isInitialIndexing
        )
    }
    
    private func calculateCostAndUnpriced(
        perModel: [String: TokenCounts],
        modelMessageCounts: [String: Int]
    ) -> (cost: Double?, unpricedCount: Int) {
        guard let pricing = self.pricingSnapshot, !pricing.prices.isEmpty else {
            let totalUnpriced = modelMessageCounts.values.reduce(0, +)
            return (nil, totalUnpriced)
        }
        
        var totalCost: Double = 0.0
        var unpricedMessages = 0
        var pricedModelCount = 0
        
        for (model, counts) in perModel {
            if let matched = CostCalculator.matchPricing(for: model, in: pricing) {
                let cost = CostCalculator.calculateCost(counts: counts, pricing: matched.pricing)
                totalCost += cost
                pricedModelCount += 1
            } else {
                unpricedMessages += modelMessageCounts[model] ?? 0
            }
        }
        
        if perModel.isEmpty {
            return (0.0, 0)
        }
        
        if pricedModelCount == 0 && !perModel.isEmpty {
            return (nil, unpricedMessages)
        }
        
        return (totalCost, unpricedMessages)
    }
    
    // MARK: - Trend Buckets for Chart
    
    public func getTrendBuckets(
        scope: TokenUsageScope,
        fiveHourWindowStart: Date?,
        now: Date = Date()
    ) -> [TrendBucket] {
        let calendar = Calendar.current
        
        switch scope {
        case .currentFiveHourWindow:
            guard let windowStart = fiveHourWindowStart else { return [] }
            let matchingRecords = recentRecords.filter { $0.timestamp >= windowStart && $0.timestamp <= now }
            var map: [String: TrendBucket] = [:]
            
            for record in matchingRecords {
                var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.timestamp)
                comps.minute = ((comps.minute ?? 0) / 30) * 30
                comps.second = 0
                comps.nanosecond = 0
                guard let bucketStart = calendar.date(from: comps) else { continue }
                
                let key = "\(bucketStart.timeIntervalSince1970)_\(record.model)"
                if var existing = map[key] {
                    existing.counts += record.counts
                    existing.messageCount += 1
                    map[key] = existing
                } else {
                    map[key] = TrendBucket(
                        bucketStart: bucketStart,
                        model: record.model,
                        counts: record.counts,
                        messageCount: 1
                    )
                }
            }
            return map.values.sorted {
                if $0.bucketStart != $1.bucketStart {
                    return $0.bucketStart < $1.bucketStart
                }
                return $0.model < $1.model
            }
            
        case .today:
            let startOfToday = calendar.startOfDay(for: now)
            let matchingRecords = recentRecords.filter { $0.timestamp >= startOfToday && $0.timestamp <= now }
            var map: [String: TrendBucket] = [:]
            
            for record in matchingRecords {
                var comps = calendar.dateComponents([.year, .month, .day, .hour], from: record.timestamp)
                comps.minute = 0
                comps.second = 0
                comps.nanosecond = 0
                guard let bucketStart = calendar.date(from: comps) else { continue }
                
                let key = "\(bucketStart.timeIntervalSince1970)_\(record.model)"
                if var existing = map[key] {
                    existing.counts += record.counts
                    existing.messageCount += 1
                    map[key] = existing
                } else {
                    map[key] = TrendBucket(
                        bucketStart: bucketStart,
                        model: record.model,
                        counts: record.counts,
                        messageCount: 1
                    )
                }
            }
            return map.values.sorted {
                if $0.bucketStart != $1.bucketStart {
                    return $0.bucketStart < $1.bucketStart
                }
                return $0.model < $1.model
            }
            
        case .thisWeek:
            let today = calendar.startOfDay(for: now)
            // Aligned to the same calendar week boundary as computeSummaries' .thisWeek scope
            // (Calendar.weekOfYear), not a rolling 7-day window — otherwise this chart would
            // disagree with the token totals shown above it for the same "This Week" scope.
            let startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today

            var map: [String: TrendBucket] = [:]

            for entry in fileIndex.values {
                for bucket in entry.aggregated {
                    if bucket.day >= startDate && bucket.day <= today {
                        let key = "\(bucket.day.timeIntervalSince1970)_\(bucket.model)"
                        if var existing = map[key] {
                            existing.counts += bucket.counts
                            existing.messageCount += bucket.messageCount
                            map[key] = existing
                        } else {
                            map[key] = TrendBucket(
                                bucketStart: bucket.day,
                                model: bucket.model,
                                counts: bucket.counts,
                                messageCount: bucket.messageCount
                            )
                        }
                    }
                }
            }
            return map.values.sorted {
                if $0.bucketStart != $1.bucketStart {
                    return $0.bucketStart < $1.bucketStart
                }
                return $0.model < $1.model
            }

        case .thisMonth:
            // Intentionally a rolling 30-day window, not calendar-month-aligned — this preserves
            // the original "30-Day Token Trend" chart behavior that predates the per-scope
            // granularity work; the chart title stays "30-Day Token Trend" for this case
            // (see TokenStatsView.trendChartTitle) precisely because it isn't the same range as
            // the "This Month" scope's calendar-month total shown above it.
            let today = calendar.startOfDay(for: now)
            guard let startDate = calendar.date(byAdding: .day, value: -29, to: today) else {
                return []
            }

            var map: [String: TrendBucket] = [:]
            
            for entry in fileIndex.values {
                for bucket in entry.aggregated {
                    if bucket.day >= startDate && bucket.day <= today {
                        let key = "\(bucket.day.timeIntervalSince1970)_\(bucket.model)"
                        if var existing = map[key] {
                            existing.counts += bucket.counts
                            existing.messageCount += bucket.messageCount
                            map[key] = existing
                        } else {
                            map[key] = TrendBucket(
                                bucketStart: bucket.day,
                                model: bucket.model,
                                counts: bucket.counts,
                                messageCount: bucket.messageCount
                            )
                        }
                    }
                }
            }
            return map.values.sorted {
                if $0.bucketStart != $1.bucketStart {
                    return $0.bucketStart < $1.bucketStart
                }
                return $0.model < $1.model
            }
        }
    }
    
    public func getAllTrendBuckets(
        fiveHourWindowStart: Date?,
        now: Date = Date()
    ) -> [TokenUsageScope: [TrendBucket]] {
        var result: [TokenUsageScope: [TrendBucket]] = [:]
        for scope in TokenUsageScope.allCases {
            result[scope] = getTrendBuckets(scope: scope, fiveHourWindowStart: fiveHourWindowStart, now: now)
        }
        return result
    }
}
