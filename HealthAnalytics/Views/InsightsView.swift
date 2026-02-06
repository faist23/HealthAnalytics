//
//  InsightsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI
import Charts

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var showACWRInfo = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Handle Loading & Error States
                if viewModel.isLoading {
                    ProgressView("Analyzing your data...")
                        .padding()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                        .cardStyle(for: .error)
                } else {
                    // 2. Main Dashboard Content (Broken into groups to fix compiler timeout)
                    dashboardContent
                }
                
                Spacer()
            }
            .padding()
        }
        .background(TabBackgroundColor.insights(for: colorScheme))
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.analyzeData()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            await viewModel.analyzeData()
        }
    }
    
    // MARK: - Sub-View Groups
    // Breaking the body into these groups solves the "Expression too complex" error
    
    @ViewBuilder
    private var dashboardContent: some View {
        Group {
            recommendationsSection
            readinessSection
            acwrTrendSection
        }
        
        Group {
            simpleInsightsSection
            recoveryStatusSection
            trainingLoadSection
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
    private var readinessSection: some View {
        if let assessment = viewModel.readinessAssessment {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text("TRAINING STATUS")
                                .font(.caption).bold().foregroundColor(.secondary)
                            
                            Button {
                                showACWRInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Text(assessment.state.label)
                            .font(.title).bold()
                            .foregroundColor(assessment.state.color)
                    }
                    Spacer()
                    Text(String(format: "%.2f", assessment.acwr))
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                }
            }
            .sheet(isPresented: $showACWRInfo) {
                ACWRInfoSheet()
            }
            .padding()
            .cardStyle(for: .recovery)
        }
    }
    
    @ViewBuilder
    private var acwrTrendSection: some View {
        if !viewModel.acwrTrend.isEmpty {
            VStack(alignment: .leading) {
                Text("7-DAY ACWR TREND")
                    .font(.caption).bold().foregroundColor(.secondary)
                    .padding(.top)
                
                Chart {
                    RectangleMark(
                        xStart: .value("Start", viewModel.acwrTrend.first?.date ?? Date()),
                        xEnd: .value("End", viewModel.acwrTrend.last?.date ?? Date()),
                        yStart: .value("Low", 0.8),
                        yEnd: .value("High", 1.3)
                    )
                    .foregroundStyle(.green.opacity(0.2))
                    .annotation(position: .overlay, alignment: .trailing) {
                        Text("Sweet Spot")
                            .font(.caption2)
                            .foregroundColor(.green.opacity(0.8))
                            .padding(.trailing, 4)
                    }
                    
                    RuleMark(y: .value("Baseline", 1.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.gray)
                    
                    ForEach(viewModel.acwrTrend) { day in
                        LineMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Ratio", day.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(viewModel.readinessAssessment?.state.color ?? .blue)
                        
                        PointMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Ratio", day.value)
                        )
                        .foregroundStyle(viewModel.readinessAssessment?.state.color ?? .blue)
                    }
                }
                .frame(height: 150)
                .chartYScale(domain: 0.5...2.0)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
            }
            .padding()
            .cardStyle(for: .recovery)
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
    private var recoveryStatusSection: some View {
        if !viewModel.recoveryInsights.isEmpty {
            Divider().padding(.vertical)
            
            Text("Recovery Status")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(viewModel.recoveryInsights, id: \.metric) { insight in
                RecoveryInsightCard(insight: insight)
            }
        }
    }
    
    @ViewBuilder
    private var trainingLoadSection: some View {
        if let trainingLoad = viewModel.trainingLoadSummary {
            Divider().padding(.vertical)
            
            Text("Training Load")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TrainingLoadCard(summary: trainingLoad)
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
            
            // 🟢 FIXED: Use 'metricName' instead of 'metric' for ID
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: insight.activityType == "Run" ? "figure.run" : "figure.outdoor.cycle")
                            Text("\(insight.activityType) Performance")
                                .font(.headline)
                            Spacer()
                            Text("\(String(format: "%.1f", insight.percentDifference))%")
                                .foregroundColor(insight.percentDifference >= 0 ? .green : .red)
                                .bold()
                        }
                        
                        Text(insight.recommendation)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Based on \(insight.sampleSize) workouts")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
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
            DataCollectionCard(summary: viewModel.dataSummary)
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
                
                VStack(spacing: 8) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(4)
        }
        .padding()
        .cardStyle(for: .info)
    }
}

struct ActivityInsightCard: View {
    let insight: CorrelationEngine.ActivityTypeInsight
    
    var insightText: String {
        let direction = insight.percentDifference > 0 ? "better" : "worse"
        let percent = abs(insight.percentDifference)
        return "You perform \(String(format: "%.1f", percent))% \(direction) after 7+ hours of sleep"
    }
    
    var activityIcon: String {
        switch insight.activityType {
        case "Run": return "figure.run"
        case "Ride", "VirtualRide": return "bicycle"
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
                ("With 7+ hrs sleep", String(format: "%.1f avg", insight.goodSleepAvg)),
                ("With <7 hrs sleep", String(format: "%.1f avg", insight.poorSleepAvg)),
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
    let summary: [(activityType: String, goodSleep: Int, poorSleep: Int)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.orange)
                
                Text("Data Collection Progress")
                    .font(.headline)
            }
            
            Text("Keep tracking! Here's what we have so far:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
            
            ForEach(summary, id: \.activityType) { item in
                HStack {
                    Text(item.activityType)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    HStack(spacing: 15) {
                        Label("\(item.goodSleep)", systemImage: "moon.zzz.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        
                        Label("\(item.poorSleep)", systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
            
            VStack(alignment: .leading, spacing: 4) {
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
                
                HStack(spacing: 8) {
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
        switch summary.status.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
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
                VStack(alignment: .leading, spacing: 4) {
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
                
                VStack(alignment: .leading, spacing: 4) {
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
            
            VStack(alignment: .leading, spacing: 4) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
                    .foregroundStyle(.red)
                
                VStack(alignment: .leading, spacing: 4) {
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
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            // Protein Ranges
            if !insight.proteinRanges.isEmpty {
                Divider()
                
                Text("Recovery by Protein Intake")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                VStack(spacing: 8) {
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
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isOptimal ? Color.green.opacity(0.1) : Color.clear)
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
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    
                    Text("\(insight.sampleSize) workouts analyzed")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("<\(Int(insight.carbThreshold))g carbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", insight.lowCarbPerformance))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("≥\(Int(insight.carbThreshold))g carbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", insight.highCarbPerformance))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(insight.percentDifference > 0 ? .green : .primary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
            
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
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
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
                        Label("0.8 - 1.3 (Sweet Spot): You are building fitness safely.", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                        Label("1.3 - 1.5 (Overreaching): You are pushing hard; monitor recovery.", systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Label("> 1.5 (Danger Zone): High risk of injury or burnout.", systemImage: "xmark.octagon.fill").foregroundColor(.red)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
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
    NavigationStack {
        InsightsView()
    }
}


