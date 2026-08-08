//
//  InsightsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    @State private var isFirstLoad = true
    @State private var isPatternAnalyzing = false
    @State private var patternAnalysisError: String?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext

    // Reactive SwiftData read — updates automatically when TrainingDNAAnalyzer persists
    @Query(sort: \TrainingPattern.confidenceNumerator, order: .reverse)
    private var storedPatterns: [TrainingPattern]

    /// Only patterns still being re-detected. Stored patterns are never deleted, so
    /// without this filter the card list showed de-detected patterns indefinitely
    /// while the tab badge and header strip (both already recency-filtered) read 0.
    private var detectedPatterns: [TrainingPattern] {
        storedPatterns.filter { $0.isActive }
    }

    @ObservedObject private var repo = ReadinessRepository.shared

    /// R.6: InsightsView is now a pure content producer. PatternsTabView owns
    /// the NavigationStack, the ScrollView, the ScrollViewReader, the
    /// background, the gear toolbar, and the cross-tab pattern-scroll handler.
    /// This kills the nested-ScrollView bug where the deep-link `proxy.scrollTo`
    /// fired against an inner ScrollView that wasn't actually scrolling.
    var body: some View {
        VStack(spacing: 20) {
            if let error = viewModel.errorMessage {
                ErrorView(message: error) {
                    Task { await viewModel.analyzeData() }
                }
                .cardStyle(for: .error)
            } else if viewModel.isLoading || isFirstLoad {
                // Lightweight inline placeholder — PatternsTabView's header strip
                // and Data sources disclosure stay visible above/below while
                // the dashboard content loads.
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading patterns…")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, .spacingLg)
            } else {
                dashboardContent
            }
        }
        .padding()
        .task {
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
            await viewModel.analyzeData()
            isFirstLoad = false
            await triggerPatternAnalysis()
        }
        .onChange(of: modelContext) { _, _ in
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataWindowChanged"))) { _ in
            Task { await viewModel.analyzeData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataSyncCompleted"))) { _ in
            Task { await viewModel.analyzeData() }
        }
    }

    // Today's Signal card removed in R.3 (v0.1.9.0 Intelligence redesign).
    // Pattern count surfaces on the Patterns tab icon badge + a quiet header
    // strip at the top of the tab (R.5). Coach owns advisory voice.

    // MARK: - Sub-View Groups
    // Breaking the body into these groups solves the "Expression too complex" error
    
    @ViewBuilder
    private var dashboardContent: some View {
        // R.2: AgingAlphaCard moved to Labs.
        // R.3: recommendationsSection deleted (advisory voice — Coach owns prescription).
        //      simpleInsightsSection + metricTrendsSection merged into whatsChangedSection
        //      under one "What's changed" header in the SimpleInsightCard design.
        //      ComingSoonCard ("Optimal Training Windows") deleted — never ship
        //      coming-soon tiles in production.
        Group {
            whatsChangedSection
        }

        Group {
            correlationsSection
        }

        // R.5: dataCollectionSection moved to PatternsTabView's collapsible
        // "Data sources" footer at the bottom of the tab.

        Group {
            trainingDNASection
        }
    }

    // MARK: - Training DNA Section (Phase 2)

    @ViewBuilder
    private var trainingDNASection: some View {
        let historyDays = UserDefaults.standard.integer(forKey: "healthKitHistoryDays")
        // historyDays == 0 means not yet calculated — hide rather than show wrong state
        if historyDays > 0 && historyDays < 45 {
            // Hidden entirely — no section
            EmptyView()
        } else if historyDays >= 45 && historyDays < 60 {
            trainingDNAProgressRow(daysNeeded: 60 - historyDays)
        } else {
            // 60+ days: show section header + cards/states
            VStack(alignment: .leading, spacing: 12) {
                Text("Training DNA")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, .spacingXs)

                if isPatternAnalyzing && detectedPatterns.isEmpty {
                    patternLoadingSkeleton
                } else if let err = patternAnalysisError {
                    patternErrorRow(message: err)
                } else if detectedPatterns.isEmpty {
                    // Distinguish "never found anything" from "found patterns before,
                    // none still hold" — the second is a real, informative state.
                    if storedPatterns.isEmpty {
                        trainingDNAProgressRow(daysNeeded: 0)
                    } else {
                        patternsQuietRow
                    }
                } else {
                    VStack(spacing: .spacingMd) {
                        ForEach(detectedPatterns) { pattern in
                            TrainingDNACard(pattern: pattern)
                                .id(pattern.patternType)
                        }
                    }

                    // Partial state: patterns not yet surfaced
                    let missingTypes = PatternType.allCases.filter { type in
                        !detectedPatterns.map(\.patternType).contains(type)
                    }
                    if !missingTypes.isEmpty && historyDays < 90 {
                        let names = missingTypes.map(\.displayName).joined(separator: " + ")
                        let weeksLeft = max(1, Int(ceil(Double(90 - historyDays) / 7.0)))
                        Text("\(names) need\(missingTypes.count == 1 ? "s" : "") \(weeksLeft) more week\(weeksLeft == 1 ? "" : "s") of data")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, .spacingXs)
                    }
                }
            }
        }
    }

    private var patternsQuietRow: some View {
        Text("No patterns active this week — nothing in your recent training stands out. Past patterns return here when they show up again.")
            .font(.system(size: 13, weight: .regular, design: .default))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, .spacingXs)
    }

    private func trainingDNAProgressRow(daysNeeded: Int) -> some View {
        let weeksLeft = daysNeeded > 0 ? max(1, Int(ceil(Double(daysNeeded) / 7.0))) : nil
        let message: String = weeksLeft != nil
            ? "Training DNA is building — check back in ~\(weeksLeft!) week\(weeksLeft! == 1 ? "" : "s")"
            : "Training DNA analyzing — no qualifying training blocks detected yet. Keep training consistently."
        return Text(message)
            .font(.system(size: 13, weight: .regular, design: .default))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, .spacingXs)
    }

    /// Inline skeleton shown while pattern analysis is running for the first time
    private var patternLoadingSkeleton: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color.surface)
                .frame(height: 120)
                .overlay(
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surfaceRaised)
                            .frame(width: 160, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surfaceRaised)
                            .frame(width: 240, height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surfaceRaised)
                            .frame(height: 20)
                            .padding(.top, 4)
                    }
                    .padding(.spacingMd)
                    .frame(maxWidth: .infinity, alignment: .leading),
                    alignment: .leading
                )
                .opacity(0.7)
        }
    }

    private func patternErrorRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.statusWarning)
            Text(message)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button("Try again") {
                Task { await triggerPatternAnalysis(force: true) }
            }
            .font(.system(size: 13, weight: .medium, design: .default))
            .foregroundStyle(Color.accent)
        }
        .padding(.spacingMd)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
        .frame(minHeight: 44)
    }

    // MARK: - Pattern Analysis Trigger

    @MainActor
    private func triggerPatternAnalysis(force: Bool = false) async {
        isPatternAnalyzing = true
        patternAnalysisError = nil
        await ReadinessRepository.shared.runPatternAnalysis(
            container: modelContext.container,
            force: force
        )
        isPatternAnalyzing = false
    }

    // MARK: - Individual Sections

    // recommendationsSection removed in R.3 — RecommendationCard list duplicated
    // the Master Coach paragraph's purpose in a different voice. Coach owns
    // advisory prose on the Coach tab (Phase 2.4); no other tab should
    // re-introduce it. The underlying ActionableRecommendations engine still
    // runs (cheap) — its output is just no longer rendered.
    
    @ViewBuilder
    private var trainingLoadSection: some View {
        if let assessment = viewModel.readinessAssessment,
           !viewModel.acwrTrend.isEmpty {
            UnifiedTrainingLoadCard(
                assessment: assessment,
                trend: viewModel.acwrTrend,
                summary: viewModel.trainingLoadSummary,
                primaryActivity: viewModel.primaryActivity,
                extendedData: viewModel.loadVisualization
            )
            .cardStyle(for: .workouts)
        }
    }
    
    /// "What's changed" section — dedupe-by-metric merge of MetricTrend +
    /// SimpleInsight data. For metrics that both sources compute (RHR, HRV,
    /// Sleep Duration, Steps, Weight, Training Frequency), MetricTrend wins —
    /// it has structured baseline + % change + direction. SimpleInsight
    /// supplies the unique narrative entries (e.g. Sleep Consistency).
    /// All cards render in the SimpleInsightCard design with explicit
    /// "vs your 21-day baseline" language so the user always knows what the
    /// number is being compared to.
    @ViewBuilder
    private var whatsChangedSection: some View {
        let ordered = orderedWhatsChanged
        if !ordered.isEmpty {
            Text("What's changed")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(ordered, id: \.title) { insight in
                SimpleInsightCard(insight: insight)
            }
        }
    }

    /// Build the ordered list of "What's changed" cards. MetricTrends drive
    /// the primary order (RHR → HRV → Sleep Duration → Daily Steps → Weight →
    /// Training Frequency). Sleep Consistency, the only meaningful unique
    /// SimpleInsight after dedupe, is injected right after Sleep Duration so
    /// the two sleep cards sit together. Any other future uniques fall at end.
    private var orderedWhatsChanged: [CorrelationEngine.SimpleInsight] {
        let coveredDomains = Set(viewModel.metricTrends.map { domainKey(forMetricTrend: $0.metricName) })
        let uniqueStories = viewModel.simpleInsights.filter { insight in
            !coveredDomains.contains(domainKey(forSimpleInsightTitle: insight.title))
        }
        var ordered: [CorrelationEngine.SimpleInsight] = []
        for trend in viewModel.metricTrends {
            ordered.append(mapTrendToInsight(trend))
            if trend.metricName == "Sleep Duration",
               let consistency = uniqueStories.first(where: { $0.title == "Sleep Consistency" }) {
                ordered.append(consistency)
            }
        }
        for story in uniqueStories where story.title != "Sleep Consistency" {
            ordered.append(story)
        }
        return ordered
    }

    /// Map a structured MetricTrend into a SimpleInsight whose description
    /// names the averaging window AND the baseline window in plain English.
    /// The user shouldn't have to guess what "45 bpm" represents — it's a
    /// 7-day rolling average, and the comparison is against the prior 21 days.
    private func mapTrendToInsight(_ trend: MetricTrend) -> CorrelationEngine.SimpleInsight {
        let style = metricStyle(for: trend.metricName)
        let formattedValue = style.formatter(trend.currentValue)

        let description: String
        if trend.metricName == "Training Frequency" {
            // Training Frequency is a per-week rate computed from a 30-day window.
            description = "Averaged over the last 30 days."
        } else if let baseline = trend.baselineValue, abs(trend.percentageChange) >= 1.0 {
            let direction = trend.percentageChange > 0 ? "Up" : "Down"
            let absPct = Int(abs(trend.percentageChange).rounded())
            let baselineFormatted = style.formatter(baseline)
            description = "7-day average. \(direction) \(absPct)% vs your 21-day baseline (\(baselineFormatted))."
        } else if let baseline = trend.baselineValue {
            // < 1% change — call it stable, but still name both windows.
            description = "7-day average. Stable vs your 21-day baseline (\(style.formatter(baseline)))."
        } else {
            description = "7-day average. \(trend.context)"
        }

        return CorrelationEngine.SimpleInsight(
            title: trend.metricName,
            value: formattedValue,
            description: description,
            icon: style.icon,
            iconColor: style.color
        )
    }

    /// Visual style per metric — icon glyph, value formatter (units), and
    /// SimpleInsightCard color key. New metric names should be added here.
    private func metricStyle(for name: String) -> (icon: String, formatter: (Double) -> String, color: String) {
        switch name {
        case "Resting Heart Rate":
            return ("heart.fill", { String(format: "%.0f bpm", $0) }, "red")
        case "HRV":
            return ("waveform.path.ecg", { String(format: "%.0f ms", $0) }, "green")
        case "Sleep Duration":
            return ("bed.double.fill", { String(format: "%.1f hrs", $0) }, "blue")
        case "Daily Steps":
            return ("figure.walk", { String(format: "%.0f", $0.rounded()) }, "orange")
        case "Body Weight":
            return ("scalemass.fill", { String(format: "%.1f lbs", $0) }, "orange")
        case "Training Frequency":
            return ("figure.run", { String(format: "%.1f/wk", $0) }, "orange")
        default:
            return ("chart.line.uptrend.xyaxis", { String(format: "%.1f", $0) }, "gray")
        }
    }

    /// Canonical domain key for dedupe between MetricTrend.metricName and
    /// SimpleInsight.title (which name the same metric differently — e.g.
    /// MetricTrend "HRV" vs SimpleInsight "Recovery Status").
    private func domainKey(forMetricTrend name: String) -> String { name }
    private func domainKey(forSimpleInsightTitle title: String) -> String {
        switch title {
        case "Recovery Status":      return "HRV"
        case "Resting Heart Rate":   return "Resting Heart Rate"
        case "Training Frequency":   return "Training Frequency"
        default:                     return title // unique stories (e.g. "Sleep Consistency") stay distinct
        }
    }
    
    /// R.4 merge: five separate correlation sections (Sleep & Performance,
    /// HRV & Performance, Protein & Recovery, Protein & Performance, Carbs &
    /// Performance) collapsed into one CorrelationsCard with a segmented
    /// control (Sleep / HRV / Protein / Carbs). The two protein sections
    /// share the Protein segment.
    @ViewBuilder
    private var correlationsSection: some View {
        let hasAny = !viewModel.activityTypeInsights.isEmpty
            || !viewModel.hrvPerformanceInsights.isEmpty
            || (viewModel.proteinRecoveryInsight != nil && viewModel.proteinRecoveryInsight?.confidence != .insufficient)
            || !viewModel.proteinPerformanceInsights.isEmpty
            || !viewModel.carbPerformanceInsights.isEmpty

        if hasAny {
            Divider().padding(.vertical)
            CorrelationsCard(
                activityInsights: viewModel.activityTypeInsights,
                hrvInsights: viewModel.hrvPerformanceInsights,
                proteinRecovery: viewModel.proteinRecoveryInsight,
                proteinPerformance: viewModel.proteinPerformanceInsights,
                carbInsights: viewModel.carbPerformanceInsights
            )
        }
    }
    
    // dataCollectionSection moved to PatternsTabView's "Data sources" disclosure
    // footer in R.5. DataCollectionCard itself stays defined in this file —
    // PatternsTabView consumes it directly.


    private func trendLabel(for trend: PredictiveReadinessService.ReadinessAssessment.Trend) -> String {
        switch trend {
        case .overreaching: return "Overreaching"
        case .building: return "Building"
        case .optimal: return "Optimal"
        case .detraining: return "Detraining"
        }
    }

    private func trendColor(for trend: PredictiveReadinessService.ReadinessAssessment.Trend) -> Color {
        switch trend {
        case .overreaching: return .red
        case .building: return .orange
        case .optimal: return .green
        case .detraining: return .blue
        }
    }
}

struct InsightCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let insight: String
    let details: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                
                Text(title)
                    .font(.headline)
                
                Spacer()
            }
            
            Text(insight)
                .font(.body)
                .foregroundStyle(.primary)
            
            if !details.isEmpty {
                Divider()
                
                VStack(spacing: .spacingSm) {
                    ForEach(details, id: \.0) { detail in
                        HStack {
                            Text(detail.0)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(detail.1)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle(for: .info)
    }
}

struct ComingSoonCard: View {
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("Coming soon")
                .font(.caption)
                .padding(.horizontal, .spacingSm)
                .padding(.vertical, .spacingXs)
                .background(Color(.systemGray5))
                .cornerRadius(4)
        }
        .padding()
        .cardStyle(for: .info)
    }
}

struct ActivityInsightCard: View {
    let insight: CorrelationEngine.ActivityTypeInsight
    
    // Determine unit based on activity type
    var unitLabel: String {
        let type = insight.activityType.lowercased()
        if type.contains("ride") || type.contains("cycling") || type.contains("virtual") {
            return "W"   // Cycling = Watts
        } else {
            return "mph" // Running/Walking = Speed
        }
    }
    
    var insightText: String {
        let direction = insight.percentDifference > 0 ? "better" : "worse"
        let percent = abs(insight.percentDifference)
        return "You perform \(String(format: "%.1f", percent))% \(direction) after 7+ hours of sleep"
    }
    
    var activityIcon: String {
        switch insight.activityType {
        case "Run": return "figure.run"
        case "Ride", "VirtualRide", "Cycling": return "bicycle" // Added Cycling case just in case
        case "Walk": return "figure.walk"
        case "Hike": return "figure.hiking"
        case "Swim": return "figure.pool.swim"
        default: return "figure.mixed.cardio"
        }
    }
    
    var body: some View {
        InsightCard(
            title: "\(insight.activityType) & Sleep",
            icon: activityIcon,
            iconColor: .blue,
            insight: insightText,
            details: [
                ("With 7+ hrs sleep", String(format: "%.1f %@", insight.goodSleepAvg, unitLabel)),
                ("With <7 hrs sleep", String(format: "%.1f %@", insight.poorSleepAvg, unitLabel)),
                ("Sample size", "\(insight.sampleSize) workouts")
            ]
        )
    }
}

struct EmptyInsightsView: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Not Enough Data Yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Keep tracking your sleep and workouts to unlock personalized insights. We need at least 3 workouts of the same type with both good and poor sleep.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct DataCollectionCard: View {
    struct ActivitySummary: Identifiable {
        let id = UUID()
        let activityType: String
        let goodSleep: Int
        let poorSleep: Int
    }

    let summary: [ActivitySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.statusWarning)

                Text("Data Collection Progress")
                    .font(.headline)
            }

            Text("Keep tracking! Here's what we have so far:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(summary) { item in
                HStack {
                    Text(item.activityType)
                        .font(.subheadline)

                    Spacer()

                    HStack(spacing: 15) {
                        Label("\(item.goodSleep)", systemImage: "moon.zzz.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusOptimal)

                        Label("\(item.poorSleep)", systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusWarning)
                    }
                }
            }
            
            Text("Need 2+ workouts with good sleep (7+ hrs) AND 2+ with poor sleep (<7 hrs) for each activity type")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding()
        .cardStyle(for: .info)
    }
}

/// R.4 — unified correlations surface. Replaces five separate sections
/// (Sleep & Performance, HRV & Performance, Protein & Recovery,
/// Protein & Performance, Carbs & Performance) with one card and a
/// segmented control. Each segment falls back to a brief empty state
/// when its data isn't ready yet, so the user knows what's coming
/// rather than wondering why a segment exists at all.
struct CorrelationsCard: View {
    let activityInsights: [CorrelationEngine.ActivityTypeInsight]
    let hrvInsights: [CorrelationEngine.HRVPerformanceInsight]
    let proteinRecovery: NutritionCorrelationEngine.ProteinRecoveryInsight?
    let proteinPerformance: [NutritionCorrelationEngine.ProteinPerformanceInsight]
    let carbInsights: [NutritionCorrelationEngine.CarbPerformanceInsight]

    enum Segment: String, CaseIterable, Identifiable {
        case sleep   = "Sleep"
        case hrv     = "HRV"
        case protein = "Protein"
        case carbs   = "Carbs"
        var id: String { rawValue }
    }

    @State private var selected: Segment

    init(activityInsights: [CorrelationEngine.ActivityTypeInsight],
         hrvInsights: [CorrelationEngine.HRVPerformanceInsight],
         proteinRecovery: NutritionCorrelationEngine.ProteinRecoveryInsight?,
         proteinPerformance: [NutritionCorrelationEngine.ProteinPerformanceInsight],
         carbInsights: [NutritionCorrelationEngine.CarbPerformanceInsight]) {
        self.activityInsights = activityInsights
        self.hrvInsights = hrvInsights
        self.proteinRecovery = proteinRecovery
        self.proteinPerformance = proteinPerformance
        self.carbInsights = carbInsights
        // Default the segment to the first one that actually has data so the
        // user lands on something useful instead of an empty placeholder.
        let defaultSegment: Segment = {
            if !activityInsights.isEmpty { return .sleep }
            if !hrvInsights.isEmpty { return .hrv }
            let proteinReady = (proteinRecovery != nil && proteinRecovery?.confidence != .insufficient)
                || !proteinPerformance.isEmpty
            if proteinReady { return .protein }
            if !carbInsights.isEmpty { return .carbs }
            return .sleep
        }()
        self._selected = State(initialValue: defaultSegment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            Text("Correlations")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: $selected) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Group {
                switch selected {
                case .sleep:   sleepContent
                case .hrv:     hrvContent
                case .protein: proteinContent
                case .carbs:   carbsContent
                }
            }
        }
    }

    @ViewBuilder private var sleepContent: some View {
        if activityInsights.isEmpty {
            emptyState("Log a few weeks of workouts and we'll show how your sleep affects them.")
        } else {
            ForEach(activityInsights, id: \.activityType) { insight in
                ActivityInsightCard(insight: insight)
                    .cardStyle(for: .sleep)
            }
        }
    }

    @ViewBuilder private var hrvContent: some View {
        if hrvInsights.isEmpty {
            emptyState("We need more HRV samples linked to workouts before we can show a pattern.")
        } else {
            ForEach(hrvInsights, id: \.activityType) { insight in
                HRVInsightCard(insight: insight)
            }
        }
    }

    @ViewBuilder private var proteinContent: some View {
        let recoveryReady = proteinRecovery != nil && proteinRecovery?.confidence != .insufficient
        if !recoveryReady && proteinPerformance.isEmpty {
            emptyState("Log a few weeks of nutrition data to see protein patterns.")
        } else {
            if let recovery = proteinRecovery, recovery.confidence != .insufficient {
                ProteinRecoveryCard(insight: recovery)
            }
            ForEach(proteinPerformance, id: \.activityType) { insight in
                VStack(alignment: .leading, spacing: .spacingSm) {
                    HStack {
                        Image(systemName: insight.activityType == "Run" ? "figure.run" : "figure.outdoor.cycle")
                        Text("\(insight.activityType) Performance")
                            .font(.headline)
                        Spacer()
                        Text("\(String(format: "%.1f", insight.percentDifference))%")
                            .foregroundStyle(insight.percentDifference >= 0 ? .green : .red)
                            .bold()
                    }
                    Text(insight.recommendation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Based on \(insight.sampleSize) workouts")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                .padding(.vertical, .spacingXs)
            }
        }
    }

    @ViewBuilder private var carbsContent: some View {
        if carbInsights.isEmpty {
            emptyState("Log a few weeks of nutrition data to see carb patterns.")
        } else {
            ForEach(carbInsights, id: \.analysisType) { insight in
                CarbPerformanceCard(insight: insight)
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, .spacingLg)
    }
}

struct SimpleInsightCard: View {
    let insight: CorrelationEngine.SimpleInsight
    
    var iconColor: Color {
        switch insight.iconColor {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: insight.icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: .spacingXs) {
                Text(insight.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(insight.value)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .cardStyle(for: .info)
    }
}

struct RecoveryInsightCard: View {
    let insight: CorrelationEngine.RecoveryInsight
    
    var trendColor: Color {
        switch insight.trend {
        case .recovered: return .green
        case .recovering: return .orange
        case .fatigued: return .red
        case .stable: return .blue
        }
    }
    
    var body: some View {
        HStack(spacing: 15) {
            Text(insight.trend.emoji)
                .font(.system(size: 40))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.metric)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: .spacingSm) {
                    Text(String(format: "%.0f", insight.currentValue))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(trendColor)
                    
                    Text("(baseline: \(String(format: "%.0f", insight.baselineValue)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(insight.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .cardStyle(for: .recovery)
    }
}

struct HRVInsightCard: View {
    let insight: CorrelationEngine.HRVPerformanceInsight
    
    var activityIcon: String {
        switch insight.activityType {
        case "Run": return "figure.run"
        case "Ride", "VirtualRide": return "bicycle"
        default: return "figure.mixed.cardio"
        }
    }
    
    var body: some View {
        InsightCard(
            title: "\(insight.activityType) & HRV",
            icon: activityIcon,
            iconColor: .green,
            insight: insight.insightText,
            details: [
                ("High HRV", String(format: "%.1f avg", insight.highHRVAvg)),
                ("Low HRV", String(format: "%.1f avg", insight.lowHRVAvg)),
                ("Sample size", "\(insight.sampleSize) workouts")
            ]
        )
    }
}

struct TrainingLoadCard: View {
    let summary: TrainingLoadCalculator.TrainingLoadSummary
    
    var statusColor: Color {
        return summary.status.color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(summary.status.emoji)
                    .font(.system(size: 40))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Acute:Chronic Ratio")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(String(format: "%.2f", summary.acuteChronicRatio))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                
                Spacer()
            }
            
            Divider()
            
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text("Acute Load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f", summary.acuteLoad))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("7-day avg")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text("Chronic Load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f", summary.chronicLoad))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("28-day avg")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Divider()
            
            Text(summary.recommendation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .cardStyle(for: .workouts)
   }
}

struct TrendCard: View {
    let trend: MetricTrend
    
    var body: some View {
        HStack(spacing: 15) {
            // Emoji for direction
            Text(trend.trendDirection.emoji)
                .font(.system(size: 32))
            
            VStack(alignment: .leading, spacing: .spacingXs) {
                // Metric Name
                Text(trend.metricName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Context / Value
                Text(trend.context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Current Value Display
                Text("Current: \(String(format: "%.1f", trend.currentValue))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Status Badge
            Text(trend.status.rawValue.capitalized)
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, .spacingSm)
                .padding(.vertical, .spacingXs)
                .background(trend.status.color.opacity(0.15))
                .foregroundStyle(trend.status.color)
                .cornerRadius(6)
        }
        .padding()
        .cardStyle(for: .info)
    }
}

struct RecommendationCard: View {
    let recommendation: ActionableRecommendations.Recommendation
    
    var priorityColor: Color {
        switch recommendation.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(recommendation.priority.emoji)
                    .font(.title2)
                
                Text(recommendation.title)
                    .font(.headline)
                    .foregroundStyle(priorityColor)
                
                Spacer()
            }
            
            Text(recommendation.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recommendation.actionItems, id: \.self) { action in
                    if action.isEmpty {
                        // Empty line for spacing
                        Spacer()
                            .frame(height: 4)
                    } else if !action.trimmingCharacters(in: .whitespaces).starts(with: "•") {
                        // Section headers (no bullet)
                        Text(action.trimmingCharacters(in: .whitespaces))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    } else {
                        // Bullet points
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(priorityColor)
                                .frame(width: 10, alignment: .leading)
                            
                            Text(action.trimmingCharacters(in: .whitespaces).dropFirst(2)) // Remove bullet and space
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle(for: .workouts)
    }
}

struct ProteinRecoveryCard: View {
    let insight: NutritionCorrelationEngine.ProteinRecoveryInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header
            HStack {
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(Color.statusWarning)

                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text("Protein Optimization")
                        .font(.headline)
                    
                    Text("Current avg: \(Int(insight.currentAverage))g/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(insight.confidence.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Recommendation
            Text(insight.recommendation)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding()
                .background(Color.statusRest.opacity(0.1))
                .cornerRadius(.radiusSm)

            // Protein Ranges
            if !insight.proteinRanges.isEmpty {
                Divider()
                
                Text("Recovery by Protein Intake")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                VStack(spacing: .spacingSm) {
                    ForEach(insight.proteinRanges, id: \.range) { range in
                        ProteinRangeRow(
                            range: range,
                            isOptimal: range.range == insight.optimalProteinRange?.range
                        )
                    }
                }
            }
        }
        .padding()
        .cardStyle(for: .nutrition)
    }
}

struct ProteinRangeRow: View {
    let range: NutritionCorrelationEngine.ProteinRecoveryInsight.ProteinRange
    let isOptimal: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Range label
            Text(range.range)
                .font(.caption)
                .fontWeight(isOptimal ? .bold : .regular)
                .foregroundStyle(isOptimal ? .green : .primary)
                .frame(width: 80, alignment: .leading)
            
            // HRV indicator
            if let hrv = range.avgHRV {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HRV")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(hrv))ms")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(width: 60)
            }
            
            // RHR indicator
            if let rhr = range.avgRHR {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RHR")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(rhr))bpm")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(width: 60)
            }
            
            Spacer()
            
            // Sample size
            Text("\(range.sampleSize)d")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Optimal badge
            if isOptimal {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Color.statusOptimal)
            }
        }
        .padding(.vertical, .spacingXs)
        .padding(.horizontal, .spacingSm)
        .background(isOptimal ? Color.statusOptimal.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

struct CarbPerformanceCard: View {
    let insight: NutritionCorrelationEngine.CarbPerformanceInsight
    
    var title: String {
        switch insight.analysisType {
        case .preworkout: return "Previous Day Carbs"
        case .postworkout: return "Post-Workout Refueling"
        case .dailyTotal: return "Same-Day Carbs"
        }
    }
    
    var icon: String {
        switch insight.analysisType {
        case .preworkout: return "moon.fill"
        case .postworkout: return "clock.arrow.circlepath"
        case .dailyTotal: return "calendar"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.statusOptimal)

                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text(title)
                        .font(.headline)

                    Text("\(insight.sampleSize) cycling workouts analyzed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(insight.confidence.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Performance comparison
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text("<\(Int(insight.carbThreshold))g carbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", insight.lowCarbPerformance))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("avg watts")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text("≥\(Int(insight.carbThreshold))g carbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", insight.highCarbPerformance))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(insight.percentDifference > 0 ? .green : .primary)
                    Text("avg watts")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(.radiusSm)
            
            // Difference badge
            if abs(insight.percentDifference) >= 5 {
                HStack {
                    Image(systemName: insight.percentDifference > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(insight.percentDifference > 0 ? .green : .orange)
                    
                    Text("\(String(format: "%.1f", abs(insight.percentDifference)))% \(insight.percentDifference > 0 ? "better" : "worse") with higher carbs")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal)
            }
            
            // Recommendation
            Text(insight.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color.statusOptimal.opacity(0.1))
                .cornerRadius(.radiusSm)
        }
        .padding()
        .cardStyle(for: .nutrition)
   }
}

struct ACWRInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("What is ACWR?")) {
                    Text("The Acute:Chronic Workload Ratio (ACWR) compares your training load from the last 7 days (Fatigue) to your average load over the last 28 days (Fitness).")
                }
                
                Section(header: Text("Understanding the Number")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("0.8 - 1.3 (Sweet Spot): You are building fitness safely.", systemImage: "checkmark.circle.fill").foregroundStyle(Color.statusOptimal)
                        Label("1.3 - 1.5 (Overreaching): You are pushing hard; monitor recovery.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.statusMonitoring)
                        Label("> 1.5 (Danger Zone): High risk of injury or burnout.", systemImage: "xmark.octagon.fill").foregroundStyle(Color.statusWarning)
                    }
                    .font(.subheadline)
                    .padding(.vertical, .spacingSm)
                }
            }
            .navigationTitle("Training Load Explained")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }
}

// Make AnalysisType Identifiable
extension NutritionCorrelationEngine.CarbPerformanceInsight.AnalysisType: Identifiable {
    var id: String {
        switch self {
        case .preworkout: return "preworkout"
        case .postworkout: return "postworkout"
        case .dailyTotal: return "dailyTotal"
        }
    }
}

#Preview {
    InsightsView()
}


