import SwiftUI
import Charts

enum TokenType: String, CaseIterable, Identifiable {
    case input, output, cacheRead, cacheWrite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .input: return "Input Tokens"
        case .output: return "Output Tokens"
        case .cacheRead: return "Cache Read Tokens"
        case .cacheWrite: return "Cache Write Tokens"
        }
    }

    var color: Color {
        switch self {
        case .input: return .blue
        case .output: return .green
        case .cacheRead: return .purple
        case .cacheWrite: return .orange
        }
    }

    func value(from counts: TokenCounts) -> Int {
        switch self {
        case .input: return counts.input
        case .output: return counts.output
        case .cacheRead: return counts.cacheRead
        case .cacheWrite: return counts.cacheCreationTotal
        }
    }

    var shortLabel: String {
        switch self {
        case .input: return "In"
        case .output: return "Out"
        case .cacheRead: return "CR"
        case .cacheWrite: return "CW"
        }
    }
}

struct TokenStatsView: View {
    @ObservedObject var viewModel: WidgetViewModel
    @State private var selectedScope: TokenUsageScope = .currentFiveHourWindow
    @State private var isPerModelExpanded: Bool = false
    @State private var hoverBucketDate: Date? = nil
    @State private var visibleTokenTypes: Set<TokenType> = TokenStatsView.loadVisibleTokenTypes()

    private static let visibleTokenTypesDefaultsKey = "visibleTokenTypes"

    private static func loadVisibleTokenTypes() -> Set<TokenType> {
        guard let saved = UserDefaults.standard.array(forKey: visibleTokenTypesDefaultsKey) as? [String] else {
            return Set(TokenType.allCases)
        }
        return Set(saved.compactMap(TokenType.init(rawValue:)))
    }

    private func saveVisibleTokenTypes() {
        UserDefaults.standard.set(visibleTokenTypes.map(\.rawValue), forKey: Self.visibleTokenTypesDefaultsKey)
    }

    private func setTokenType(_ type: TokenType, visible: Bool) {
        if visible {
            visibleTokenTypes.insert(type)
        } else {
            visibleTokenTypes.remove(type)
        }
        saveVisibleTokenTypes()
    }

    /// Sums only the currently checked token types — used so the bars and the trend chart
    /// rescale to whatever's selected instead of always being dominated by cache volume.
    private func filteredValue(for counts: TokenCounts) -> Int {
        TokenType.allCases.reduce(0) { partial, type in
            visibleTokenTypes.contains(type) ? partial + type.value(from: counts) : partial
        }
    }

    // MARK: - Model Filter
    // Deselection is exclusion-based (not inclusion-based) so any model key in
    // summary.perModel is shown unless the user has explicitly hidden it.
    @State private var deselectedModels: Set<String> = []

    private func isModelVisible(_ model: String) -> Bool {
        !deselectedModels.contains(model)
    }

    private func filteredCounts(from summary: TokenUsageSummary) -> TokenCounts {
        summary.perModel.reduce(into: TokenCounts()) { partial, entry in
            if isModelVisible(entry.key) {
                partial += entry.value
            }
        }
    }
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    private static let chartDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 14) {
            // Scope Picker
            Picker("Scope", selection: $selectedScope) {
                ForEach(TokenUsageScope.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 2)

            Divider()

            tokenTypeFilterSection

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // Token Counts Section
                    if let summary = viewModel.tokenUsage[selectedScope] {
                        if selectedScope == .currentFiveHourWindow && !viewModel.isFiveHourWindowAvailable {
                            unstartedFiveHourBanner
                        } else {
                            tokenCountsRows(summary: summary)
                        }
                    } else if viewModel.isScanningTranscripts {
                        HStack {
                            Spacer()
                            ProgressView("Indexing transcripts…")
                                .padding()
                            Spacer()
                        }
                    } else {
                        Text("No transcript data available.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    
                    Divider()
                    
                    // 30-Day Trend Chart
                    trendChartSection
                    
                    Divider()
                    
                    // Per-Model Breakdown
                    if let summary = viewModel.tokenUsage[selectedScope], !summary.perModel.isEmpty {
                        perModelBreakdownSection(summary: summary)
                        Divider()
                    }
                    
                    // Cost & Reference Footer
                    footerSection
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .frame(minWidth: 580, minHeight: 480)
    }
    
    // MARK: - Token Type Filter

    private var tokenTypeFilterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Token Types Shown")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button(visibleTokenTypes.count == TokenType.allCases.count ? "Deselect All" : "Select All") {
                    visibleTokenTypes = visibleTokenTypes.count == TokenType.allCases.count ? [] : Set(TokenType.allCases)
                    saveVisibleTokenTypes()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            HStack(spacing: 14) {
                ForEach(TokenType.allCases) { type in
                    Toggle(isOn: Binding(
                        get: { visibleTokenTypes.contains(type) },
                        set: { setTokenType(type, visible: $0) }
                    )) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(type.color)
                                .frame(width: 6, height: 6)
                            Text(type.displayName)
                                .font(.caption)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    // MARK: - Subviews

    private var unstartedFiveHourBanner: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack {
                Spacer()
                Text("—")
                    .font(.title.bold())
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text("Waiting for Claude quota data")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("The 5-hour window usage will align once active quota resets_at is available.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
    
    private func tokenCountsRows(summary: TokenUsageSummary) -> some View {
        let counts = filteredCounts(from: summary)
        let visibleTypes = TokenType.allCases.filter { visibleTokenTypes.contains($0) }
        let maxVal = max(visibleTypes.map { $0.value(from: counts) }.max() ?? 0, 1)
        let allModelsDeselected = !summary.perModel.isEmpty && summary.perModel.keys.allSatisfy { !isModelVisible($0) }

        return VStack(alignment: .leading, spacing: 10) {
            if visibleTypes.isEmpty {
                Text("No token types selected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else if allModelsDeselected {
                Text("No models selected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(visibleTypes) { type in
                    tokenRow(
                        title: type.displayName,
                        count: type.value(from: counts),
                        maxCount: maxVal,
                        color: type.color,
                        subtitle: type == .cacheWrite && counts.cacheCreationTotal > 0
                            ? "5m: \(TokenFormatter.formatNumber(counts.cacheCreation5m)) · 1h: \(TokenFormatter.formatNumber(counts.cacheCreation1h))"
                            : nil
                    )
                }
            }
        }
    }
    
    private func tokenRow(
        title: String,
        count: Int,
        maxCount: Int,
        color: Color,
        subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text(TokenFormatter.formatNumber(count))
                    .font(.system(.body, design: .monospaced).bold())
                Text("(\(TokenFormatter.formatCompact(count)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geo in
                let fraction = CGFloat(count) / CGFloat(maxCount)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(geo.size.width * fraction, count > 0 ? 3 : 0), height: 6)
                }
            }
            .frame(height: 6)
            
            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Trend Chart
    
    private var trendChartTitle: String {
        switch selectedScope {
        case .currentFiveHourWindow:
            return "5-Hour Token Trend"
        case .today:
            return "Today's Token Trend"
        case .thisWeek:
            return "This Week's Token Trend"
        case .thisMonth:
            return "30-Day Token Trend"
        }
    }
    
    private var currentTrendBuckets: [TrendBucket] {
        (viewModel.trendBuckets[selectedScope] ?? []).filter { isModelVisible($0.model) }
    }
    
    private var trendTotals: [(bucketStart: Date, total: Int)] {
        var map: [Date: Int] = [:]
        for bucket in currentTrendBuckets {
            map[bucket.bucketStart, default: 0] += filteredValue(for: bucket.counts)
        }
        return map.keys.sorted().map { ($0, map[$0] ?? 0) }
    }

    private var chartYAxisUpperBound: Double {
        let peak: Int
        if isPerModelExpanded {
            // AreaMark with foregroundStyle(by:) stacks marks sharing an x position, so the
            // domain must equal the summed per-bucket total across all visible models.
            var stackedTotals: [Date: Int] = [:]
            for bucket in currentTrendBuckets {
                stackedTotals[bucket.bucketStart, default: 0] += filteredValue(for: bucket.counts)
            }
            peak = stackedTotals.values.max() ?? 0
        } else {
            peak = trendTotals.map(\.total).max() ?? 0
        }
        return Double(max(peak, 1)) * 1.15
    }
    
    private var chartCalendarUnit: Calendar.Component {
        switch selectedScope {
        case .currentFiveHourWindow:
            return .minute
        case .today:
            return .hour
        case .thisWeek, .thisMonth:
            return .day
        }
    }

    private func nearestTrendTotal(to date: Date) -> (bucketStart: Date, total: Int)? {
        trendTotals.min { lhs, rhs in
            abs(lhs.bucketStart.timeIntervalSince(date)) < abs(rhs.bucketStart.timeIntervalSince(date))
        }
    }

    private func hoverLabel(for date: Date) -> String {
        switch selectedScope {
        case .currentFiveHourWindow, .today:
            return Self.timeFormatter.string(from: date)
        case .thisWeek, .thisMonth:
            return Self.chartDateFormatter.string(from: date)
        }
    }

    private var trendChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trendChartTitle)
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Spacer()
                if isPerModelExpanded {
                    Text("Per-Model Breakdown")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                } else {
                    Text("Total Volume")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if selectedScope == .currentFiveHourWindow && !viewModel.isFiveHourWindowAvailable {
                HStack {
                    Spacer()
                    Text("Waiting for Claude quota data…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 30)
                    Spacer()
                }
            } else if visibleTokenTypes.isEmpty {
                HStack {
                    Spacer()
                    Text("No token types selected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 30)
                    Spacer()
                }
            } else if currentTrendBuckets.isEmpty && !(viewModel.trendBuckets[selectedScope] ?? []).isEmpty {
                HStack {
                    Spacer()
                    Text("No models selected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 30)
                    Spacer()
                }
            } else if currentTrendBuckets.isEmpty {
                HStack {
                    Spacer()
                    Text("No historical trend data available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                Chart {
                    if isPerModelExpanded {
                        ForEach(currentTrendBuckets) { bucket in
                            AreaMark(
                                x: .value("Date", bucket.bucketStart, unit: chartCalendarUnit),
                                y: .value("Tokens", filteredValue(for: bucket.counts))
                            )
                            .foregroundStyle(by: .value("Model", bucket.model))
                        }
                    } else {
                        ForEach(trendTotals, id: \.bucketStart) { item in
                            AreaMark(
                                x: .value("Date", item.bucketStart, unit: chartCalendarUnit),
                                y: .value("Tokens", item.total)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                        }
                    }

                    if let hoverBucketDate, let match = nearestTrendTotal(to: hoverBucketDate) {
                        RuleMark(x: .value("Date", match.bucketStart, unit: chartCalendarUnit))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .annotation(position: .top, alignment: .center, spacing: 4) {
                                VStack(spacing: 2) {
                                    Text(hoverLabel(for: match.bucketStart))
                                        .font(.caption2.bold())
                                    Text("\(TokenFormatter.formatCompact(match.total)) tokens")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(6)
                                .background(.regularMaterial)
                                .cornerRadius(6)
                            }
                    }
                }
                .chartXAxis {
                    chartXAxisMarks
                }
                .chartYScale(domain: 0...chartYAxisUpperBound)
                .chartYAxis {
                    AxisMarks { value in
                        if let intVal = value.as(Int.self) {
                            AxisValueLabel {
                                Text(TokenFormatter.formatCompact(intVal))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 140)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let plotFrame = geometry[proxy.plotAreaFrame]
                                    let xInPlot = location.x - plotFrame.origin.x
                                    guard xInPlot >= 0, xInPlot <= plotFrame.width,
                                          let date: Date = proxy.value(atX: xInPlot) else {
                                        hoverBucketDate = nil
                                        return
                                    }
                                    hoverBucketDate = date
                                case .ended:
                                    hoverBucketDate = nil
                                }
                            }
                    }
                }
            }
        }
        .onChange(of: selectedScope) { _ in
            hoverBucketDate = nil
        }
    }
    
    @AxisContentBuilder
    private var chartXAxisMarks: some AxisContent {
        switch selectedScope {
        case .currentFiveHourWindow:
            AxisMarks(values: .stride(by: .minute, count: 30)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(Self.timeFormatter.string(from: date))
                            .font(.caption2)
                    }
                }
                AxisGridLine()
                AxisTick()
            }
        case .today:
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(Self.timeFormatter.string(from: date))
                            .font(.caption2)
                    }
                }
                AxisGridLine()
                AxisTick()
            }
        case .thisWeek:
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(Self.chartDateFormatter.string(from: date))
                            .font(.caption2)
                    }
                }
                AxisGridLine()
                AxisTick()
            }
        case .thisMonth:
            AxisMarks(values: .stride(by: .day, count: 5)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(Self.chartDateFormatter.string(from: date))
                            .font(.caption2)
                    }
                }
                AxisGridLine()
                AxisTick()
            }
        }
    }
    
    // MARK: - Per-Model Breakdown
    
    private func perModelBreakdownSection(summary: TokenUsageSummary) -> some View {
        DisclosureGroup("Per-Model Breakdown", isExpanded: $isPerModelExpanded) {
            perModelBreakdownContent(summary: summary)
        }
        .disclosureGroupStyle(FullWidthDisclosureGroupStyle())
        .font(.subheadline)
    }

    private func perModelBreakdownContent(summary: TokenUsageSummary) -> some View {
            let visibleTypes = TokenType.allCases.filter { visibleTokenTypes.contains($0) }
            let allModels = summary.perModel.keys.sorted()

            return VStack(alignment: .leading, spacing: 8) {
                if visibleTypes.isEmpty {
                    Text("No token types selected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(allModels, id: \.self) { model in
                        if let modelCounts = summary.perModel[model] {
                            let isVisible = isModelVisible(model)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { isModelVisible(model) },
                                        set: { isOn in
                                            if isOn {
                                                deselectedModels.remove(model)
                                            } else {
                                                deselectedModels.insert(model)
                                            }
                                        }
                                    )) {
                                        Text(model)
                                            .font(.subheadline.bold())
                                    }
                                    .toggleStyle(.checkbox)
                                    Spacer()
                                    Text("Total: \(TokenFormatter.formatCompact(filteredValue(for: modelCounts)))")
                                        .font(.caption.bold())
                                }

                                HStack(spacing: 12) {
                                    ForEach(visibleTypes) { type in
                                        Text("\(type.shortLabel): \(TokenFormatter.formatCompact(type.value(from: modelCounts)))")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .opacity(isVisible ? 1.0 : 0.4)
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }

                if allModels.count > 1 && !allModels.allSatisfy(isModelVisible) {
                    Text("Unchecked models are excluded from the totals and chart above.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if summary.unpricedMessageCount > 0 {
                    Text("\(summary.unpricedMessageCount) messages used an unrecognized model and are not included in the cost estimate.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 4)
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        let summary = viewModel.tokenUsage[selectedScope]
        let costString: String
        if selectedScope == .currentFiveHourWindow && !viewModel.isFiveHourWindowAvailable {
            costString = "—"
        } else if let cost = summary?.estimatedCostUSD {
            costString = TokenFormatter.formatUSD(cost)
        } else if summary?.unpricedMessageCount ?? 0 > 0 && summary?.counts.total ?? 0 > 0 {
            costString = "— (pricing unavailable, tap Rescan to retry)"
        } else {
            costString = "—"
        }
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Estimated Cost:")
                    .font(.headline)
                Text(costString)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text("Reference only — estimated at pay-as-you-go API rates. Your Pro/Max subscription is billed at a flat monthly rate; this is not a bill.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                if viewModel.isScanningTranscripts {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Scanning transcripts & fetching pricing…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let lastDate = viewModel.lastTokenScanDate {
                    Text("Last scanned \(Self.timeFormatter.string(from: lastDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.refreshTokenUsage(forcePricingRefresh: true)
                }) {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isScanningTranscripts)
            }
        }
        .padding(.top, 4)
    }
}

/// Makes the whole label row tappable to expand/collapse, not just the small native disclosure
/// triangle — the default triangle-only tap target is too small to hit reliably.
private struct FullWidthDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
