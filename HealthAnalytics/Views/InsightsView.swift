//
//  InsightsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                if viewModel.isLoading {
                    ProgressView("Analyzing your data...")
                        .padding()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                } else {
                    // Recommendations (high priority items at top)
                    if !viewModel.recommendations.isEmpty {
                        ForEach(viewModel.recommendations, id: \.title) { recommendation in
                            RecommendationCard(recommendation: recommendation)
                        }
                        
                        Divider()
                            .padding(.vertical)
                    }
                    
                    // Simple insights (always available)
                    if !viewModel.simpleInsights.isEmpty {
                        Text("Your Health Trends")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(viewModel.simpleInsights, id: \.title) { insight in
                            SimpleInsightCard(insight: insight)
                        }
                        
                        Divider()
                            .padding(.vertical)
                    }
                    
                    // Recovery Status
                    if !viewModel.recoveryInsights.isEmpty {
                        Divider()
                            .padding(.vertical)
                        
                        Text("Recovery Status")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(viewModel.recoveryInsights, id: \.metric) { insight in
                            RecoveryInsightCard(insight: insight)
                        }
                    }
                    
                    // Training Load
                    if let trainingLoad = viewModel.trainingLoadSummary {
                        Divider()
                            .padding(.vertical)
                        
                        Text("Training Load")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        TrainingLoadCard(summary: trainingLoad)
                    }
                    
                    // Metric Trends
                    if !viewModel.metricTrends.isEmpty {
                        Divider()
                            .padding(.vertical)
                        
                        Text("Trends")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(viewModel.metricTrends, id: \.metric) { trend in
                            TrendCard(trend: trend)
                        }
                    }
                    
                    // HRV vs Performance
                    if !viewModel.hrvPerformanceInsights.isEmpty {
                        Divider()
                            .padding(.vertical)
                        
                        Text("HRV & Performance")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(viewModel.hrvPerformanceInsights, id: \.activityType) { insight in
                            HRVInsightCard(insight: insight)
                        }
                    }
                    
                    // Protein & Recovery
                    if let proteinInsight = viewModel.proteinRecoveryInsight,
                       proteinInsight.confidence != .insufficient {
                        Divider()
                            .padding(.vertical)
                        
                        Text("Protein & Recovery")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ProteinRecoveryCard(insight: proteinInsight)
                    }
                    
                    // Carbs & Performance
                    if !viewModel.carbPerformanceInsights.isEmpty {
                        Divider()
                            .padding(.vertical)
                        
                        Text("Carbs & Performance")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(viewModel.carbPerformanceInsights, id: \.analysisType) { insight in
                            CarbPerformanceCard(insight: insight)
                        }
                    }
                    
                    // Activity-specific insights (when enough data)
                    if !viewModel.activityTypeInsights.isEmpty {
                        Divider()
                            .padding(.vertical)
                        
                        Text("Sleep & Performance")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(viewModel.activityTypeInsights, id: \.activityType) { insight in
                            ActivityInsightCard(insight: insight)
                        }
                    }
                    
                    // Data collection progress
                    if !viewModel.dataSummary.isEmpty && viewModel.activityTypeInsights.isEmpty {
                        DataCollectionCard(summary: viewModel.dataSummary)
                    }
                    
                    // Placeholder for future insights
                    ComingSoonCard(title: "Recovery & Training Load")
                    ComingSoonCard(title: "Heart Rate Trends")
                    ComingSoonCard(title: "Optimal Training Windows")
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
    
    private func sleepInsightDetails(_ insight: CorrelationEngine.SleepPerformanceInsight) -> [(String, String)] {
        var details: [(String, String)] = []
        
        if insight.confidence != .insufficient {
            details.append(("With 7+ hrs sleep", String(format: "%.1f avg", insight.averagePerformanceWithGoodSleep)))
            details.append(("With <7 hrs sleep", String(format: "%.1f avg", insight.averagePerformanceWithPoorSleep)))
            details.append(("Sample size", "\(insight.sampleSize) workouts"))
        }
        
        return details
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct TrendCard: View {
    let trend: TrendDetector.MetricTrend
    
    var trendColor: Color {
        switch trend.direction.color {
        case "green": return .green
        case "orange": return .orange
        case "blue": return .blue
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 15) {
            Text(trend.direction.emoji)
                .font(.system(size: 32))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(trend.metric)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(trend.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Over \(trend.period)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .background(priorityColor.opacity(0.1))
        .cornerRadius(12)
/*        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(priorityColor.opacity(0.3), lineWidth: 1)
        )*/
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
