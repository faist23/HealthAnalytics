//
//  RecoveryDashboardView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/28/26.
//

import SwiftUI
import Charts

struct RecoveryDashboardView: View {
    @StateObject private var viewModel = RecoveryViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Today's Readiness Card (Hero) - Use yesterday's data since today is incomplete
                if let yesterday = viewModel.recoveryData.dropLast().last {
                    TodayReadinessCard(data: yesterday)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Multi-Metric Recovery Chart
                if !viewModel.recoveryData.isEmpty {
                    RecoveryMetricsChart(data: viewModel.recoveryData, period: viewModel.selectedPeriod)
                }
                
                // Individual Metric Cards
                MetricBreakdownCards(data: viewModel.recoveryData)
                
                // Weekly Summary
                if !viewModel.recoveryData.isEmpty {
                    WeeklySummaryCard(data: viewModel.recoveryData)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Time Period", selection: $viewModel.selectedPeriod) {
                        ForEach(TimePeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedPeriod.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadRecoveryData()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .onChange(of: viewModel.selectedPeriod) { oldValue, newValue in
            Task {
                await viewModel.loadRecoveryData()
            }
        }
        .task {
            await viewModel.loadRecoveryData()
        }
        .overlay {
            if viewModel.isLoading {
                LoadingOverlay()
            }
        }
    }
}

// MARK: - Today's Readiness Card (Hero)

struct TodayReadinessCard: View {
    let data: DailyRecoveryData
    
    var body: some View {
        VStack(spacing: 20) {
            // Score Circle
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 180, height: 180)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: (data.readinessScore ?? 0) / 100)
                    .stroke(
                        gradientForScore(data.readinessScore ?? 0),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: data.readinessScore)
                
                // Score text
                VStack(spacing: 4) {
                    Text("\(Int(data.readinessScore ?? 0))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            gradientForScore(data.readinessScore ?? 0)
                        )
                    
                    Text("Readiness")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            
            // Status Badge
            if let level = data.readinessLevel {
                HStack(spacing: 8) {
                    Text(level.emoji)
                        .font(.title3)
                    
                    Text(level.rawValue)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(colorForLevel(level).opacity(0.15))
                )
                .foregroundStyle(colorForLevel(level))
            }
            
            // Description
            if let level = data.readinessLevel {
                Text(level.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Divider()
                .padding(.horizontal)
            
            // Quick Stats
            HStack(spacing: 24) {
                if let rhr = data.restingHR {
                    QuickStat(
                        icon: "heart.fill",
                        value: "\(Int(rhr))",
                        label: "RHR",
                        color: .red
                    )
                }
                
                if let hrv = data.hrv {
                    QuickStat(
                        icon: "waveform.path.ecg",
                        value: "\(Int(hrv))",
                        label: "HRV",
                        color: .green
                    )
                }
                
                if let sleep = data.sleepHours {
                    QuickStat(
                        icon: "bed.double.fill",
                        value: String(format: "%.1f", sleep),
                        label: "Sleep",
                        color: .purple
                    )
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        )
    }
    
    private func gradientForScore(_ score: Double) -> LinearGradient {
        if score >= 85 {
            return LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if score >= 70 {
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if score >= 55 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private func colorForLevel(_ level: ReadinessLevel) -> Color {
        switch level {
        case .excellent: return .green
        case .good: return .blue
        case .moderate: return .orange
        case .poor: return .red
        }
    }
}

struct QuickStat: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Multi-Metric Recovery Chart

struct RecoveryMetricsChart: View {
    let data: [DailyRecoveryData]
    let period: TimePeriod
    
    @State private var selectedMetrics: Set<MetricType> = [.hrv, .rhr, .sleep]
    
    enum MetricType: String, CaseIterable, Identifiable {
        case hrv = "HRV"
        case rhr = "RHR"
        case sleep = "Sleep"
        
        var id: String { rawValue }
        
        var color: Color {
            switch self {
            case .hrv: return .green
            case .rhr: return .red
            case .sleep: return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .hrv: return "waveform.path.ecg"
            case .rhr: return "heart.fill"
            case .sleep: return "bed.double.fill"
            }
        }
    }
    
    // Calculate averages for normalization
    var hrvAvg: Double {
        let values = data.compactMap { $0.hrv }.filter { $0 > 0 }
        return values.isEmpty ? 50 : values.reduce(0, +) / Double(values.count)
    }
    
    var rhrAvg: Double {
        let values = data.compactMap { $0.restingHR }.filter { $0 > 0 }
        return values.isEmpty ? 60 : values.reduce(0, +) / Double(values.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Recovery Metrics")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Metric toggles
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MetricType.allCases) { metric in
                        MetricToggle(
                            metric: metric,
                            isSelected: selectedMetrics.contains(metric)
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedMetrics.contains(metric) {
                                    selectedMetrics.remove(metric)
                                } else {
                                    selectedMetrics.insert(metric)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Chart - show each metric separately for clarity
            if selectedMetrics.isEmpty {
                Text("Select metrics to display")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 16) {
                    ForEach(Array(selectedMetrics).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { metric in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: metric.icon)
                                    .font(.caption)
                                    .foregroundStyle(metric.color)
                                Text(metric.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(averageText(for: metric))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            
                            Chart {
                                ForEach(data.filter { hasValue(for: $0, metric: metric) }) { day in
                                    if let value = getValue(for: day, metric: metric) {
                                        LineMark(
                                            x: .value("Date", day.date),
                                            y: .value("Value", value)
                                        )
                                        .foregroundStyle(metric.color)
                                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                                        .symbol(Circle().strokeBorder(lineWidth: 2))
                                        .symbolSize(40)
                                        
                                        AreaMark(
                                            x: .value("Date", day.date),
                                            y: .value("Value", value)
                                        )
                                        .foregroundStyle(metric.color.opacity(0.1))
                                    }
                                }
                                
                                // Baseline reference
                                if metric == .hrv || metric == .rhr {
                                    RuleMark(y: .value("Average", getBaseline(for: metric)))
                                        .foregroundStyle(.gray.opacity(0.3))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                }
                            }
                            .frame(height: 80)
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisValueLabel {
                                        if let doubleValue = value.as(Double.self) {
                                            Text(formatValue(doubleValue, for: metric))
                                                .font(.caption2)
                                        }
                                    }
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                        .foregroundStyle(.gray.opacity(0.2))
                                }
                            }
                            .chartXAxis {
                                AxisMarks { value in
                                    if let date = value.as(Date.self) {
                                        AxisValueLabel {
                                            Text(date, format: .dateTime.month(.abbreviated).day())
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .padding(.vertical)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 15, y: 8)
        )
    }
    
    private func hasValue(for day: DailyRecoveryData, metric: MetricType) -> Bool {
        switch metric {
        case .hrv: return day.hrv != nil && day.hrv! > 0
        case .rhr: return day.restingHR != nil && day.restingHR! > 0
        case .sleep: return day.sleepHours != nil && day.sleepHours! > 0
        }
    }
    
    private func getValue(for day: DailyRecoveryData, metric: MetricType) -> Double? {
        switch metric {
        case .hrv: return day.hrv
        case .rhr: return day.restingHR
        case .sleep: return day.sleepHours
        }
    }
    
    private func getBaseline(for metric: MetricType) -> Double {
        switch metric {
        case .hrv: return hrvAvg
        case .rhr: return rhrAvg
        case .sleep: return 7.5
        }
    }
    
    private func averageText(for metric: MetricType) -> String {
        switch metric {
        case .hrv: return "Avg: \(Int(hrvAvg)) ms"
        case .rhr: return "Avg: \(Int(rhrAvg)) bpm"
        case .sleep:
            let values = data.compactMap { $0.sleepHours }.filter { $0 > 0 }
            let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            return "Avg: \(String(format: "%.1f", avg)) hrs"
        }
    }
    
    private func formatValue(_ value: Double, for metric: MetricType) -> String {
        switch metric {
        case .hrv, .rhr:
            return "\(Int(value))"
        case .sleep:
            return String(format: "%.1f", value)
        }
    }
}

struct MetricToggle: View {
    let metric: RecoveryMetricsChart.MetricType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: metric.icon)
                    .font(.caption)
                
                Text(metric.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? metric.color.opacity(0.2) : Color(.systemGray6))
            )
            .foregroundStyle(isSelected ? metric.color : .secondary)
            .overlay(
                Capsule()
                    .strokeBorder(metric.color.opacity(isSelected ? 0.6 : 0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric Breakdown Cards

struct MetricBreakdownCards: View {
    let data: [DailyRecoveryData]
    
    // Use yesterday's data since today is incomplete
    var latestHRV: Double? {
        data.dropLast().last(where: { $0.hrv != nil && $0.hrv! > 0 })?.hrv
    }
    
    var latestRHR: Double? {
        data.dropLast().last(where: { $0.restingHR != nil && $0.restingHR! > 0 })?.restingHR
    }
    
    var latestSleep: Double? {
        data.dropLast().last(where: { $0.sleepHours != nil && $0.sleepHours! > 0 })?.sleepHours
    }
    
    var avgHRV: Double {
        let values = data.compactMap { $0.hrv }.filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    var avgRHR: Double {
        let values = data.compactMap { $0.restingHR }.filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    var avgSleep: Double {
        let values = data.compactMap { $0.sleepHours }.filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Metric Details")
                .font(.title3)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                if let hrv = latestHRV {
                    MetricCard(
                        title: "HRV",
                        icon: "waveform.path.ecg",
                        value: "\(Int(hrv))",
                        unit: "ms",
                        trend: hrv > avgHRV ? .up : .down,
                        color: .green,
                        subtitle: "Avg: \(Int(avgHRV)) ms"
                    )
                }
                
                if let rhr = latestRHR {
                    MetricCard(
                        title: "Resting HR",
                        icon: "heart.fill",
                        value: "\(Int(rhr))",
                        unit: "bpm",
                        trend: rhr < avgRHR ? .up : .down,
                        color: .red,
                        subtitle: "Avg: \(Int(avgRHR)) bpm"
                    )
                }
                
                if let sleep = latestSleep {
                    MetricCard(
                        title: "Sleep",
                        icon: "bed.double.fill",
                        value: String(format: "%.1f", sleep),
                        unit: "hrs",
                        trend: sleep >= 7 ? .up : .down,
                        color: .purple,
                        subtitle: "Avg: \(String(format: "%.1f", avgSleep)) hrs"
                    )
                }
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let trend: TrendDirection
    let color: Color
    let subtitle: String
    
    enum TrendDirection {
        case up, down, neutral
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "minus"
            }
        }
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .orange
            case .neutral: return .gray
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                
                Spacer()
                
                Image(systemName: trend.icon)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(trend.color)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(trend.color.opacity(0.15))
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        )
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    let data: [DailyRecoveryData]
    
    var weeklyAvgReadiness: Double {
        let lastWeek = data.suffix(7)
        let scores = lastWeek.compactMap { $0.readinessScore }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }
    
    var excellentDays: Int {
        data.suffix(7).filter { ($0.readinessLevel == .excellent) }.count
    }
    
    var poorDays: Int {
        data.suffix(7).filter { ($0.readinessLevel == .poor) }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("7-Day Summary")
                .font(.title3)
                .fontWeight(.bold)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Average Readiness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(Int(weeklyAvgReadiness))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(excellentDays) excellent")
                            .font(.caption)
                    }
                    
                    if poorDays > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("\(poorDays) poor")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 15, y: 8)
        )
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                
                Text("Loading Recovery Data...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(radius: 30)
            )
        }
    }
}

#Preview {
    NavigationStack {
        RecoveryDashboardView()
    }
}
