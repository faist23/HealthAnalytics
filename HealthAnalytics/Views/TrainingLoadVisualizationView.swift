//
//  TrainingLoadVisualizationView.swift
//  HealthAnalytics
//
//  Interactive training load visualization with charts
//

import SwiftUI
import Charts

struct TrainingLoadVisualizationView: View {
    let data: TrainingLoadVisualizationService.LoadVisualizationData
    @State private var selectedTab: LoadView = .timeSeries
    
    enum LoadView: String, CaseIterable {
        case timeSeries = "Timeline"
        case breakdown = "Breakdown"
        case weekly = "Weekly"
        
        var icon: String {
            switch self {
            case .timeSeries: return "chart.xyaxis.line"
            case .breakdown: return "chart.pie"
            case .weekly: return "calendar"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Summary Card
                LoadSummaryCard(summary: data.summary)
                
                // Tab Picker
                Picker("View", selection: $selectedTab) {
                    ForEach(LoadView.allCases, id: \.self) { view in
                        Label(view.rawValue, systemImage: view.icon)
                            .tag(view)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Content based on selected tab
                switch selectedTab {
                case .timeSeries:
                    ACWRTimeSeriesChart(data: data.timeSeriesData, dangerZones: data.dangerZones)
                        .frame(height: 300)
                        .padding(.horizontal)
                    
                case .breakdown:
                    IntentBreakdownView(breakdown: data.intentBreakdown)
                        .padding(.horizontal)
                    
                case .weekly:
                    WeeklyPatternView(pattern: data.weeklyPattern)
                        .padding(.horizontal)
                }
                
                // Danger Zones (if any)
                if !data.dangerZones.isEmpty {
                    DangerZonesSection(zones: data.dangerZones)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Training Load")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Load Summary Card

struct LoadSummaryCard: View {
    let summary: TrainingLoadVisualizationService.LoadVisualizationData.LoadSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(summary.currentStatus)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(statusColor)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(String(format: "%.2f", summary.currentACWR))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                    
                    Text("ACWR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Metrics
            HStack(spacing: 20) {
                MetricPill(
                    label: "Days in status",
                    value: "\(summary.daysInCurrentStatus)",
                    icon: "calendar"
                )
                
                if let weeks = summary.weeksSinceLastDanger {
                    MetricPill(
                        label: "Weeks since danger",
                        value: "\(weeks)",
                        icon: "checkmark.shield"
                    )
                }
            }
            
            Divider()
            
            // Recommendation
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                
                Text(summary.recommendation)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
    
    private var statusColor: Color {
        switch summary.currentStatus {
        case "Optimal": return .green
        case "Building": return .orange
        case "Overreaching": return .red
        case "Detraining": return .blue
        default: return .gray
        }
    }
}

struct MetricPill: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ACWR Time Series Chart

struct ACWRTimeSeriesChart: View {
    let data: [TrainingLoadVisualizationService.LoadVisualizationData.LoadDataPoint]
    let dangerZones: [TrainingLoadVisualizationService.LoadVisualizationData.DangerZone]
  
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACWR Trend")
                .font(.headline)
            
            Chart {
                // Optimal zone reference
                RectangleMark(
                    yStart: .value("Min", 0.8),
                    yEnd: .value("Max", 1.3)
                )
                .foregroundStyle(.green.opacity(0.1))
                
                // ACWR line
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("ACWR", point.acwr)
                    )
                    .foregroundStyle(point.status.color)
                }
                
                // Selection point
                if let selectedDate = selectedDate,
                   let selected = data.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("ACWR", selected.acwr)
                    )
                    .foregroundStyle(selected.status.color)
                    .symbolSize(100)
                    
                    RuleMark(
                        x: .value("Date", selected.date)
                    )
                    .foregroundStyle(.gray.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .chartYScale(domain: 0...2.5)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartXSelection(value: $selectedDate)
            
            // Popup overlay
            if let selectedDate = selectedDate,
               let selected = data.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ACWR")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", selected.acwr))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(selected.status.color)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(selected.status.color)
                                    .frame(width: 8, height: 8)
                                Text(statusLabel(selected.status))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)
                .transition(.opacity)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func statusLabel(_ status: TrainingLoadVisualizationService.LoadVisualizationData.LoadDataPoint.LoadStatus) -> String {
        switch status {
        case .optimal: return "Optimal"
        case .building: return "Building"
        case .danger: return "Danger"
        case .detraining: return "Low"
        }
    }
}

// MARK: - Intent Breakdown

struct IntentBreakdownView: View {
    let breakdown: [TrainingLoadVisualizationService.LoadVisualizationData.IntentLoadBreakdown]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Load by Intent")
                .font(.headline)
            
            ForEach(breakdown) { item in
                IntentLoadRow(item: item)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct IntentLoadRow: View {
    let item: TrainingLoadVisualizationService.LoadVisualizationData.IntentLoadBreakdown
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(item.intent.emoji)
                    .font(.title3)
                
                Text(item.intent.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(item.percentage))%")
                    .font(.headline)
                    .foregroundStyle(intentColor(for: item.intent))
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(intentColor(for: item.intent).opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(intentColor(for: item.intent))
                        .frame(width: geo.size.width * (item.percentage / 100))
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("\(item.workoutCount) workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Avg intensity: \(String(format: "%.1f", item.avgIntensity))/10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func intentColor(for intent: ActivityIntent) -> Color {
        return intent.color
    }
}

// MARK: - Weekly Pattern

struct WeeklyPatternView: View {
    let pattern: TrainingLoadVisualizationService.LoadVisualizationData.WeeklyLoadPattern
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Weekly Pattern")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: trendIcon)
                        .foregroundColor(trendColor)
                    
                    Text(trendLabel)
                        .font(.caption)
                        .foregroundColor(trendColor)
                }
            }
            
            Chart(pattern.weeks) { week in
                BarMark(
                    x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Load", week.totalLoad)
                )
                .foregroundStyle(.blue)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            
            HStack {
                Text("Average weekly load:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(String(format: "%.0f", pattern.averageWeeklyLoad))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var trendIcon: String {
        switch pattern.trend {
        case .increasing: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .decreasing: return "arrow.down.right"
        }
    }
    
    private var trendColor: Color {
        switch pattern.trend {
        case .increasing: return .green
        case .stable: return .blue
        case .decreasing: return .orange
        }
    }
    
    private var trendLabel: String {
        switch pattern.trend {
        case .increasing: return "Increasing"
        case .stable: return "Stable"
        case .decreasing: return "Decreasing"
        }
    }
}

// MARK: - Danger Zones Section

struct DangerZonesSection: View {
    let zones: [TrainingLoadVisualizationService.LoadVisualizationData.DangerZone]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Overload Periods", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            
            ForEach(zones) { zone in
                DangerZoneCard(zone: zone)
            }
        }
        .padding()
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DangerZoneCard: View {
    let zone: TrainingLoadVisualizationService.LoadVisualizationData.DangerZone
    
    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(zone.severity.color)
                
                Text(String(format: "%.2f", zone.peakACWR))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(zone.reason)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(zone.startDate.formatted(date: .abbreviated, time: .omitted)) - \(zone.endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        TrainingLoadVisualizationView(
            data: TrainingLoadVisualizationService.LoadVisualizationData(
                timeSeriesData: [],
                intentBreakdown: [],
                weeklyPattern: TrainingLoadVisualizationService.LoadVisualizationData.WeeklyLoadPattern(
                    weeks: [],
                    averageWeeklyLoad: 500,
                    trend: .stable
                ),
                dangerZones: [],
                summary: TrainingLoadVisualizationService.LoadVisualizationData.LoadSummary(
                    currentACWR: 1.15,
                    currentStatus: "Optimal",
                    daysInCurrentStatus: 12,
                    weeksSinceLastDanger: 3,
                    projectedLoadNextWeek: 520,
                    recommendation: "Well balanced. Safe to maintain or gradually increase."
                )
            )
        )
    }
}
