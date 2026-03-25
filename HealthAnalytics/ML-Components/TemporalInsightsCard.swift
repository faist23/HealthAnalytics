//
//  TemporalInsightsCard.swift
//  HealthAnalytics
//
//  Display multi-timescale performance analysis
//

import SwiftUI
import Charts

struct TemporalInsightsCard: View {
    let analysis: TemporalModelingService.TemporalAnalysis
    @State private var selectedTab: TimeScale = .recency
    
    enum TimeScale: String, CaseIterable {
        case recency = "Recent"
        case seasonal = "Seasonal"
        case longitudinal = "Long-term"
        
        var icon: String {
            switch self {
            case .recency: return "calendar"
            case .seasonal: return "leaf"
            case .longitudinal: return "chart.line.uptrend.xyaxis"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header with synthesis
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temporal Analysis")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Text(analysis.synthesis.confidence.emoji)
                        .font(.title3)
                }
                
                Text(analysis.synthesis.headline)
                    .font(.headline)
                    .foregroundStyle(Color.accent)
            }
            
            // Time scale picker
            Picker("Time Scale", selection: $selectedTab) {
                ForEach(TimeScale.allCases, id: \.self) { scale in
                    Label(scale.rawValue, systemImage: scale.icon)
                        .tag(scale)
                }
            }
            .pickerStyle(.segmented)
            
            // Content based on selected tab
            switch selectedTab {
            case .recency:
                RecencyView(analysis: analysis.recency)
            case .seasonal:
                SeasonalView(analysis: analysis.seasonal)
            case .longitudinal:
                LongitudinalView(analysis: analysis.longitudinal)
            }
            
            Divider()
            
            // Insights
            VStack(alignment: .leading, spacing: 12) {
                Label("Key Insights", systemImage: "lightbulb.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.statusMonitoring)
                
                ForEach(analysis.synthesis.insights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusOptimal)

                        Text(insight)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
            
            // Recommendation
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.statusMonitoring)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommendation")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Text(analysis.synthesis.recommendation)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            .padding()
            .background(Color.statusMonitoring.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Recency View

struct RecencyView: View {
    let analysis: TemporalModelingService.TemporalAnalysis.RecencyAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Trend indicator
            HStack(spacing: 12) {
                Text(analysis.trend.emoji)
                    .font(.system(size: 48))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("30-Day Trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(analysis.trend.description)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
            
            Divider()
            
            // Current form metrics
            VStack(spacing: 12) {
                if let power = analysis.currentForm.averagePower {
                    MetricRow(
                        icon: "bolt.fill",
                        label: "Average Power",
                        value: "\(Int(power))W",
                        color: .statusWarning
                    )
                }

                if let speed = analysis.currentForm.averageSpeed {
                    MetricRow(
                        icon: "speedometer",
                        label: "Average Speed",
                        value: String(format: "%.1f mph", speed),
                        color: .statusRest
                    )
                }

                MetricRow(
                    icon: "figure.run",
                    label: "Training Load",
                    value: "\(Int(analysis.currentForm.trainingLoad)) workouts",
                    color: .statusOptimal
                )
                
                // Consistency bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Color.accent)
                        Text("Consistency")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(analysis.currentForm.consistency * 100))%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accent)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accent.opacity(0.2))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accent)
                                .frame(width: geo.size.width * analysis.currentForm.consistency)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}

// MARK: - Seasonal View

struct SeasonalView: View {
    let analysis: TemporalModelingService.TemporalAnalysis.SeasonalAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Current season
            HStack(spacing: 12) {
                Text(analysis.currentSeasonPerformance.season.emoji)
                    .font(.system(size: 48))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.currentSeasonPerformance.season.rawValue)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("\(Int(analysis.currentSeasonPerformance.averagePerformance)) avg performance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(analysis.currentSeasonPerformance.confidence.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Year-over-year change
            if let yoy = analysis.yearOverYearChange {
                HStack {
                    Image(systemName: yoy > 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(yoy > 0 ? Color.statusOptimal : Color.statusWarning)

                    Text("Year-over-year: \(String(format: "%+.1f%%", yoy))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background((yoy > 0 ? Color.statusOptimal : Color.statusWarning).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Divider()
            
            // Seasonal breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("Performance by Season")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                ForEach(TemporalModelingService.TemporalAnalysis.SeasonalAnalysis.Season.allCases, id: \.self) { season in
                    if let metrics = analysis.seasonalPattern[season] {
                        SeasonRow(
                            season: season,
                            metrics: metrics,
                            isBest: season == analysis.bestSeason
                        )
                    }
                }
            }
        }
    }
}

struct SeasonRow: View {
    let season: TemporalModelingService.TemporalAnalysis.SeasonalAnalysis.Season
    let metrics: TemporalModelingService.TemporalAnalysis.SeasonalAnalysis.SeasonMetrics
    let isBest: Bool
    
    var body: some View {
        HStack {
            Text(season.emoji)
            
            Text(season.rawValue)
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            
            Text("\(Int(metrics.averagePerformance))")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 40, alignment: .trailing)
            
            Spacer()
            
            if isBest {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.statusMonitoring)
            }
            
            Text("n=\(metrics.sampleSize)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Longitudinal View

struct LongitudinalView: View {
    let analysis: TemporalModelingService.TemporalAnalysis.LongitudinalAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Overall trend
            VStack(alignment: .leading, spacing: 8) {
                Text("Long-term Trajectory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Image(systemName: trendIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(trendColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(analysis.overallTrend.description)
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        Text("Growth: \(String(format: "%+.1f%%", analysis.growthRate)) per year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Timespan
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.statusRest)

                Text(analysis.timespan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.statusRest.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Peak periods
            if !analysis.peakPeriods.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Peak Performance Periods")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(analysis.peakPeriods.indices, id: \.self) { index in
                        PeakPeriodRow(
                            period: analysis.peakPeriods[index],
                            rank: index + 1
                        )
                    }
                }
            }
        }
    }
    
    private var trendIcon: String {
        switch analysis.overallTrend {
        case .strengthening: return "arrow.up.right.circle.fill"
        case .plateaued: return "arrow.right.circle.fill"
        case .weakening: return "arrow.down.right.circle.fill"
        }
    }
    
    private var trendColor: Color {
        switch analysis.overallTrend {
        case .strengthening: return .statusOptimal
        case .plateaued: return .statusRest
        case .weakening: return .statusWarning
        }
    }
}

struct PeakPeriodRow: View {
    let period: TemporalModelingService.TemporalAnalysis.LongitudinalAnalysis.PeakPeriod
    let rank: Int
    
    var body: some View {
        HStack {
            Text("#\(rank)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.statusMonitoring)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDateRange(period.startDate, period.endDate))
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("\(Int(period.averagePerformance)) avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}


#Preview {
    ScrollView {
        TemporalInsightsCard(
            analysis: TemporalModelingService.TemporalAnalysis(
                recency: TemporalModelingService.TemporalAnalysis.RecencyAnalysis(
                    currentForm: TemporalModelingService.TemporalAnalysis.RecencyAnalysis.FormMetrics(
                        averagePower: 185,
                        averageSpeed: 18.5,
                        trainingLoad: 12,
                        consistency: 0.85
                    ),
                    trend: .improving(percentChange: 5.2),
                    volatility: 0.15,
                    timeWindow: "Last 30 days"
                ),
                seasonal: TemporalModelingService.TemporalAnalysis.SeasonalAnalysis(
                    currentSeasonPerformance: TemporalModelingService.TemporalAnalysis.SeasonalAnalysis.SeasonMetrics(
                        season: .winter,
                        averagePerformance: 180,
                        sampleSize: 25,
                        confidence: .high
                    ),
                    bestSeason: .summer,
                    seasonalPattern: [:],
                    yearOverYearChange: 8.5
                ),
                longitudinal: TemporalModelingService.TemporalAnalysis.LongitudinalAnalysis(
                    overallTrend: .strengthening(percentChange: 22),
                    peakPeriods: [],
                    growthRate: 3.5,
                    timespan: "2020-2025"
                ),
                synthesis: TemporalModelingService.TemporalAnalysis.TemporalSynthesis(
                    headline: "Building on Strong Foundation",
                    insights: [
                        "Recent form is improving (+5.2% over last 30 days)",
                        "Year-over-year: +8.5%",
                        "Long-term growth: +22.0%"
                    ],
                    recommendation: "Maintain current training approach",
                    confidence: .high
                )
            )
        )
        .padding()
    }
}
