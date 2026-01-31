//
//  TimelineView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/28/26.
//

import SwiftUI
import Charts
import Combine

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Date range picker
            DateRangePicker(
                startDate: $viewModel.startDate,
                endDate: $viewModel.endDate,
                onApply: {
                    Task {
                        await viewModel.loadTimelineData()
                    }
                }
            )
            .padding()
            .background(TabBackgroundColor.recovery(for: colorScheme))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Metric toggles
                    MetricToggles(selectedMetrics: $viewModel.selectedMetrics)
                    
                    // Main timeline chart
                    if !viewModel.timelineData.isEmpty {
                        TimelineChart(
                            data: viewModel.timelineData,
                            selectedMetrics: viewModel.selectedMetrics,
                            workouts: viewModel.workouts
                        )
                    }
                    
                    // Workout markers timeline
                    if !viewModel.workouts.isEmpty {
                        WorkoutTimeline(workouts: viewModel.workouts)
                    }
                    
                    // Stats summary
                    TimelineStats(
                        data: viewModel.timelineData,
                        selectedMetrics: viewModel.selectedMetrics
                    )
                }
                .padding()
            }
            .background(TabBackgroundColor.recovery(for: colorScheme))
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadTimelineData()
        }
        .overlay {
            if viewModel.isLoading {
                LoadingOverlay()
            }
        }
    }
}

// MARK: - Timeline ViewModel

@MainActor
class TimelineViewModel: ObservableObject {
    @Published var timelineData: [TimelineDataPoint] = []
    @Published var workouts: [WorkoutData] = []
    @Published var selectedMetrics: Set<TimelineMetric> = [.rhr, .hrv, .sleep, .steps, .weight]
    @Published var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @Published var endDate = Date()
    @Published var isLoading = false
    
    private let healthKitManager = HealthKitManager.shared
    
    func loadTimelineData() async {
        isLoading = true
        
        do {
            // 1. Fetch all 5 data streams concurrently
            async let rhrData = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrvData = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleepData = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let stepData = healthKitManager.fetchStepCount(startDate: startDate, endDate: endDate)
            async let weightData = healthKitManager.fetchWeight(startDate: startDate, endDate: endDate) // Ensure this method exists
            async let workoutData = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            
            // 2. Await the results
            let rhr = try await rhrData
            let hrv = try await hrvData
            let sleep = try await sleepData
            let steps = try await stepData
            let weight = try await weightData // Capture weight result
            self.workouts = try await workoutData
            
            // 3. CRITICAL: Pass all 5 arguments to combineMetrics
            self.timelineData = combineMetrics(
                rhr: rhr,
                hrv: hrv,
                sleep: sleep,
                steps: steps,
                weight: weight // <--- This must be here
            )
            
        } catch {
            print("Error loading timeline data: \(error)")
        }
        
        isLoading = false
    }
    
    private func combineMetrics(
        rhr: [HealthDataPoint],
        hrv: [HealthDataPoint],
        sleep: [HealthDataPoint],
        steps: [HealthDataPoint],
        weight: [HealthDataPoint]
    ) -> [TimelineDataPoint] {
        var dataByDate: [Date: TimelineDataPoint] = [:]
        let calendar = Calendar.current
        
        for point in rhr {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.restingHR = point.value
        }
        
        for point in hrv {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.hrv = point.value
        }
        
        for point in sleep {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.sleepHours = point.value
        }
        
        for point in steps {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.steps = point.value
        }
        
        for point in weight {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.weight = point.value
        }
        
        return dataByDate.values.sorted { $0.date < $1.date }
    }
}

struct TimelineDataPoint: Identifiable {
    let id = UUID()
    var date: Date
    var restingHR: Double?
    var hrv: Double?
    var sleepHours: Double?
    var steps: Double?
    var weight: Double?
}

enum TimelineMetric: String, CaseIterable, Identifiable {
    case rhr = "RHR"
    case hrv = "HRV"
    case sleep = "Sleep"
    case steps = "Steps"
    case weight = "Weight"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .rhr: return .red
        case .hrv: return .green
        case .sleep: return .purple
        case .steps: return .orange
        case .weight: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .rhr: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .sleep: return "bed.double.fill"
        case .steps: return "figure.walk"
        case .weight: return "scalemass.fill"
        }
    }
    
    var unit: String {
        switch self {
        case .rhr: return "bpm"
        case .hrv: return "ms"
        case .sleep: return "hrs"
        case .steps: return "steps"
        case .weight: return "lbs"
        }
    }
}

// MARK: - Date Range Picker

struct DateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void
    
    @State private var showingCustomRange = false
    @State private var selectedQuickRange: String? = "90D" // Default to match initial ViewModel state
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Date Range")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingCustomRange.toggle()
                    if showingCustomRange { selectedQuickRange = nil }
                } label: {
                    HStack(spacing: 4) {
                        Text(formattedRange)
                            .font(.subheadline)
                        Image(systemName: "calendar")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
            
            if showingCustomRange {
                VStack(spacing: 12) {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                    
                    Button("Apply") {
                        showingCustomRange = false
                        onApply()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
            }
            
            // Quick range buttons
            if !showingCustomRange {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 7 Days
                        QuickRangeButton(title: "7D", isSelected: selectedQuickRange == "7D") {
                            updateRange(days: -7, title: "7D")
                        }
                        
                        // 30 Days
                        QuickRangeButton(title: "30D", isSelected: selectedQuickRange == "30D") {
                            updateRange(days: -30, title: "30D")
                        }
                        
                        // 90 Days
                        QuickRangeButton(title: "90D", isSelected: selectedQuickRange == "90D") {
                            updateRange(days: -90, title: "90D")
                        }
                        
                        // 6 Months
                        QuickRangeButton(title: "6M", isSelected: selectedQuickRange == "6M") {
                            updateRange(months: -6, title: "6M")
                        }
                        
                        // 1 Year
                        QuickRangeButton(title: "1Y", isSelected: selectedQuickRange == "1Y") {
                            updateRange(years: -1, title: "1Y")
                        }
                    }
                }
            }
        }
    }
    
    // Helper to update dates and highlight the button
    private func updateRange(days: Int = 0, months: Int = 0, years: Int = 0, title: String) {
        let calendar = Calendar.current
        var component = DateComponents()
        component.day = days
        component.month = months
        component.year = years
        
        startDate = calendar.date(byAdding: component, to: Date()) ?? Date()
        endDate = Date()
        selectedQuickRange = title
        onApply()
    }
    
    private var formattedRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}

struct QuickRangeButton: View {
    let title: String
    let isSelected: Bool // New property for highlighting
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    Capsule()
                    // Highlight with blue when selected, otherwise system gray
                        .fill(isSelected ? Color.blue : Color(.systemGray6))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric Toggles

struct MetricToggles: View {
    @Binding var selectedMetrics: Set<TimelineMetric>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(TimelineMetric.allCases) { metric in
                        TimelineMetricToggle(
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
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
}

struct TimelineMetricToggle: View {
    let metric: TimelineMetric
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: metric.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? metric.color : .secondary)
                
                Text(metric.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? metric.color : .secondary)
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? metric.color.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(metric.color.opacity(isSelected ? 0.5 : 0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline Chart

struct TimelineChart: View {
    let data: [TimelineDataPoint]
    let selectedMetrics: Set<TimelineMetric>
    let workouts: [WorkoutData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metrics Over Time")
                .font(.headline)
                .padding(.horizontal)
            
            if selectedMetrics.isEmpty {
                Text("Select metrics above to display")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 20) {
                    // Separate chart for each metric
                    ForEach(Array(selectedMetrics).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { metric in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: metric.icon)
                                    .foregroundStyle(metric.color)
                                Text(metric.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(averageValue(for: metric))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            
                            Chart {
                                ForEach(data) { point in
                                    if let value = getValue(from: point, for: metric) {
                                        LineMark(
                                            x: .value("Date", point.date),
                                            y: .value("Value", value)
                                        )
                                        .foregroundStyle(metric.color.gradient)
                                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                                        
                                        AreaMark(
                                            x: .value("Date", point.date),
                                            y: .value("Value", value)
                                        )
                                        .foregroundStyle(metric.color.opacity(0.1).gradient)
                                    }
                                }
                            }
                            .frame(height: 100)
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisValueLabel {
                                        if let doubleValue = value.as(Double.self) {
                                            Text(formatValue(doubleValue, for: metric))
                                                .font(.caption2)
                                        }
                                    }
                                    AxisGridLine()
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
    
    private func getValue(from point: TimelineDataPoint, for metric: TimelineMetric) -> Double? {
        switch metric {
        case .rhr: return point.restingHR
        case .hrv: return point.hrv
        case .sleep: return point.sleepHours
        case .steps: return point.steps
        case .weight: return point.weight
        }
    }
    
    private func averageValue(for metric: TimelineMetric) -> String {
        let values = data.compactMap { getValue(from: $0, for: metric) }
        guard !values.isEmpty else { return "No data" }
        let avg = values.reduce(0, +) / Double(values.count)
        return "Avg: \(formatValue(avg, for: metric))"
    }
    
    private func formatValue(_ value: Double, for metric: TimelineMetric) -> String {
        switch metric {
        case .rhr, .hrv:
            return "\(Int(value))"
        case .sleep:
            return String(format: "%.1f", value)
        case .steps:
            return "\(Int(value / 1000))k"
        case .weight:
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Workout Timeline

struct WorkoutTimeline: View {
    let workouts: [WorkoutData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workouts")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(workouts) { workout in
                        WorkoutMarker(workout: workout)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
}

struct WorkoutMarker: View {
    let workout: WorkoutData
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: workout.iconName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(.orange.gradient)
                )
            
            VStack(spacing: 2) {
                Text(workout.startDate, format: .dateTime.month().day())
                    .font(.caption2)
                    .fontWeight(.medium)
                
                Text(workout.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Timeline Stats

struct TimelineStats: View {
    let data: [TimelineDataPoint]
    let selectedMetrics: Set<TimelineMetric>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Period Summary")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if selectedMetrics.contains(.rhr) {
                    StatCard(
                        icon: "heart.fill",
                        title: "Avg RHR",
                        value: "\(Int(avgRHR))",
                        unit: "bpm",
                        color: .red
                    )
                }
                
                if selectedMetrics.contains(.hrv) {
                    StatCard(
                        icon: "waveform.path.ecg",
                        title: "Avg HRV",
                        value: "\(Int(avgHRV))",
                        unit: "ms",
                        color: .green
                    )
                }
                
                if selectedMetrics.contains(.sleep) {
                    StatCard(
                        icon: "bed.double.fill",
                        title: "Avg Sleep",
                        value: String(format: "%.1f", avgSleep),
                        unit: "hrs",
                        color: .purple
                    )
                }
                
                if selectedMetrics.contains(.steps) {
                    StatCard(
                        icon: "figure.walk",
                        title: "Avg Steps",
                        value: "\(Int(avgSteps).formatted())",
                        unit: "",
                        color: .orange
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
    
    private var avgRHR: Double {
        let values = data.compactMap { $0.restingHR }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    private var avgHRV: Double {
        let values = data.compactMap { $0.hrv }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    private var avgSleep: Double {
        let values = data.compactMap { $0.sleepHours }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    private var avgSteps: Double {
        let values = data.compactMap { $0.steps }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

#Preview {
    NavigationStack {
        TimelineView()
    }
}
