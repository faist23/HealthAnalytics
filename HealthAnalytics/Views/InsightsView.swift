//
//  InsightsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                if viewModel.isLoading {
                    ProgressView("Analyzing your data...")
                        .padding()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                } else {
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
                    
                    // Activity-specific insights (when enough data)
                    if !viewModel.activityTypeInsights.isEmpty {
                        Text("Performance Correlations")
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


#Preview {
    NavigationStack {
        InsightsView()
    }
}
