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
    @EnvironmentObject var coordinator: TabCoordinator
    @StateObject private var viewModel = InsightsViewModel()
    @State private var isFirstLoad = true
    @State private var isPatternAnalyzing = false
    @State private var patternAnalysisError: String?
    @State private var pendingScroll: PatternType? = nil
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext

    // Reactive SwiftData read — updates automatically when TrainingDNAAnalyzer persists
    @Query(sort: \TrainingPattern.confidenceNumerator, order: .reverse)
    private var detectedPatterns: [TrainingPattern]

    @ObservedObject private var repo = ReadinessRepository.shared

    var body: some View {
        NavigationStack {
        ZStack {
            TabBackgroundColor.insights(for: colorScheme)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Handle Error States
                        if let error = viewModel.errorMessage {
                            ErrorView(message: error) {
                                Task { await viewModel.analyzeData() }
                            }
                            .cardStyle(for: .error)
                        } else if !viewModel.isLoading && !isFirstLoad {
                            todayInsightCard
                            // 2. Main Dashboard Content (Broken into groups to fix compiler timeout)
                            dashboardContent
                        }

                        Spacer()
                    }
                    .padding()
                }
                .onChange(of: coordinator.pendingScrollPattern) { _, newPattern in
                    guard let pattern = newPattern else { return }
                    coordinator.pendingScrollPattern = nil
                    if isFirstLoad {
                        pendingScroll = pattern
                    } else {
                        Task { @MainActor in
                            withAnimation { proxy.scrollTo(pattern, anchor: .top) }
                        }
                    }
                }
                .onChange(of: isFirstLoad) { _, loaded in
                    guard !loaded, let pattern = pendingScroll else { return }
                    pendingScroll = nil
                    Task { @MainActor in
                        withAnimation { proxy.scrollTo(pattern, anchor: .top) }
                    }
                }
            }

            // Loading overlay
            if viewModel.isLoading || isFirstLoad {
                LoadingOverlay(message: "Analyzing your data...")
            }
        }
        .navigationTitle("Intelligence")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.analyzeData()
                        // Refresh button: force pattern re-analysis unconditionally
                        UserDefaults.standard.removeObject(forKey: "lastPatternAnalysisDate")
                        await triggerPatternAnalysis()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading || isPatternAnalyzing)
            }
        }
        .task {
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
            await viewModel.analyzeData()
            isFirstLoad = false
            // Pattern analysis: primary trigger — 7-day staleness check
            await triggerPatternAnalysis()
        }
        .onChange(of: modelContext) { _, _ in
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataWindowChanged"))) { _ in
            // Force recalculation when data window changes
            Task {
                await viewModel.analyzeData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataSyncCompleted"))) { _ in
            // Refresh when new data is synced
            Task {
                await viewModel.analyzeData()
            }
        }
        } // NavigationStack
    }

    // MARK: - Today Signal Card

    @ViewBuilder
    private var todayInsightCard: some View {
        if let readiness = repo.currentReadiness {
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let activePatterns = detectedPatterns.filter { $0.detectedAt >= sevenDaysAgo }
            let topPattern = activePatterns.min(by: {
                PatternType.displayPriority($0.patternType) <
                PatternType.displayPriority($1.patternType)
            })

            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY'S SIGNAL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .tracking(1.5)
                    .textCase(.uppercase)

                if activePatterns.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityHidden(true)
                        Text("All signals quiet — everything looks good.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(readiness.coachAdvice)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.textPrimary)
                            if let top = topPattern {
                                Text("\(top.patternType.displayName) detected")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentDim)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 3)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Sub-View Groups
    // Breaking the body into these groups solves the "Expression too complex" error
    
    @ViewBuilder
    private var dashboardContent: some View {
        if let aging = viewModel.agingAssessment {
            AgingAlphaCard(assessment: aging)
                .padding(.bottom, 10)
        }
        
        Group {
            recommendationsSection
        }
        
        Group {
            simpleInsightsSection
            metricTrendsSection
        }
        
        Group {
            hrvPerformanceSection
            proteinRecoverySection
            proteinPerformanceSection
            carbPerformanceSection
        }
        
        Group {
            activityInsightsSection
            dataCollectionSection
            ComingSoonCard(title: "Optimal Training Windows")
        }

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
                    trainingDNAProgressRow(daysNeeded: 0)
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
    
    @ViewBuilder
    private var recommendationsSection: some View {
        if !viewModel.recommendations.isEmpty {
            ForEach(viewModel.recommendations, id: \.title) { recommendation in
                RecommendationCard(recommendation: recommendation)
            }
            Divider().padding(.vertical)
        }
    }
    
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
    
    @ViewBuilder
    private var simpleInsightsSection: some View {
        if !viewModel.simpleInsights.isEmpty {
            Text("Your Health Trends")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(viewModel.simpleInsights, id: \.title) { insight in
                SimpleInsightCard(insight: insight)
            }
        }
    }
    

    @ViewBuilder
    private var metricTrendsSection: some View {
        if !viewModel.metricTrends.isEmpty {
            Divider().padding(.vertical)
            
            Text("Trends")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(viewModel.metricTrends, id: \.metricName) { trend in
                TrendCard(trend: trend)
            }
        }
    }
    
    @ViewBuilder
    private var hrvPerformanceSection: some View {
        if !viewModel.hrvPerformanceInsights.isEmpty {
            Divider().padding(.vertical)
            
            Text("HRV & Performance")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(viewModel.hrvPerformanceInsights, id: \.activityType) { insight in
                HRVInsightCard(insight: insight)
            }
        }
    }
    
    @ViewBuilder
    private var proteinRecoverySection: some View {
        if let proteinInsight = viewModel.proteinRecoveryInsight,
           proteinInsight.confidence != .insufficient {
            Divider().padding(.vertical)
            
            Text("Protein & Recovery")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ProteinRecoveryCard(insight: proteinInsight)
        }
    }
    
    @ViewBuilder
    private var proteinPerformanceSection: some View {
        if !viewModel.proteinPerformanceInsights.isEmpty {
            Section(header: Text("Protein & Performance")) {
                ForEach(viewModel.proteinPerformanceInsights, id: \.activityType) { insight in
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
    }
    
    @ViewBuilder
    private var carbPerformanceSection: some View {
        if !viewModel.carbPerformanceInsights.isEmpty {
            Divider().padding(.vertical)
            
            Text("Carbs & Performance")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(viewModel.carbPerformanceInsights, id: \.analysisType) { insight in
                CarbPerformanceCard(insight: insight)
            }
        }
    }
    
    @ViewBuilder
    private var activityInsightsSection: some View {
        if !viewModel.activityTypeInsights.isEmpty {
            Divider().padding(.vertical)
            
            Text("Sleep & Performance")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(viewModel.activityTypeInsights, id: \.activityType) { insight in
                ActivityInsightCard(insight: insight)
                    .cardStyle(for: .sleep)
            }
        }
    }
    
    @ViewBuilder
    private var dataCollectionSection: some View {
        if !viewModel.dataSummary.isEmpty && viewModel.activityTypeInsights.isEmpty {
            DataCollectionCard(summary: viewModel.dataSummary.map {
                DataCollectionCard.ActivitySummary(activityType: $0.activityType, goodSleep: $0.goodSleep, poorSleep: $0.poorSleep)
            })
        }
    }
    
    private func trendLabel(for trend: PredictiveReadinessService.ReadinessAssessment.Trend) -> String {
        switch trend {
        case .building: return "Building"
        case .optimal: return "Optimal"
        case .detraining: return "Detraining"
        }
    }

    private func trendColor(for trend: PredictiveReadinessService.ReadinessAssessment.Trend) -> Color {
        switch trend {
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
            .navigationTitle("Training Readiness")
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


