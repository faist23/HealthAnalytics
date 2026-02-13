//
//  ContentView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI
import Charts

// MARK: - Smart Axis Logic
// Extension to centralize x-axis logic for all charts
extension TimePeriod {
    var xAxisStride: (component: Calendar.Component, count: Int) {
        switch self {
        case .week:      return (.day, 1)
        case .month:     return (.day, 7)
        case .quarter:   return (.day, 14) // Every 2 weeks
        case .sixMonths: return (.month, 1)
        case .year:      return (.month, 2)
        case .all:       return (.year, 1)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var syncManager = SyncManager.shared
    
    var body: some View {
        ScrollView {
            // Use LazyVStack with pinned headers
            LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                
                Section {
                    if syncManager.isBackfillingHistory {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Establishing 10-Year Baseline...")
                                .font(.headline)
                            Text("Synchronizing historical HealthKit data to calculate aging and recovery trends.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .padding(.top, 60)
                    } else if viewModel.isLoading {
                        ProgressView("Loading health data...")
                            .padding()
                            .padding(.top, 40) // Add spacing below the pinned header
                    } else if let error = viewModel.errorMessage {
                        ErrorView(message: error)
                            .cardStyle(for: .error)
                            .padding(.top, 40)
                    } else {
                        VStack(spacing: 20) {
                            // ─── Recovery Pattern ─────────
                            if !viewModel.hrvData.isEmpty && !viewModel.workouts.isEmpty {
                                RecoveryPatternCard(
                                    hrvData:   viewModel.hrvData,
                                    rhrData:   viewModel.restingHeartRateData,
                                    sleepData: viewModel.sleepData,
                                    workouts:  viewModel.workouts
                                )
                                .cardStyle(for: .recovery)
                            }
                            
                            if !viewModel.restingHeartRateData.isEmpty {
                                RestingHeartRateCard(data: viewModel.restingHeartRateData, period: viewModel.selectedPeriod)
                                    .cardStyle(for: .heartRate)
                            }
                            
                            if !viewModel.hrvData.isEmpty {
                                HRVCard(data: viewModel.hrvData, period: viewModel.selectedPeriod)
                                    .cardStyle(for: .hrv)
                            }
                            
                            if !viewModel.sleepData.isEmpty {
                                SleepCard(data: viewModel.sleepData, period: viewModel.selectedPeriod)
                                    .cardStyle(for: .sleep)
                            }
                            
                            if !viewModel.stepCountData.isEmpty {
                                StepCountCard(data: viewModel.stepCountData, period: viewModel.selectedPeriod)
                                    .cardStyle(for: .steps)
                            }
                            
                            if !viewModel.weightData.isEmpty {
                                WeightCard(data: viewModel.weightData, period: viewModel.selectedPeriod)
                                    .cardStyle(for: .nutrition)
                            }
                            
                            if !viewModel.workouts.isEmpty {
                                WorkoutSummaryCard(workouts: viewModel.workouts, period: viewModel.selectedPeriod)
                                    //.cardStyle(for: .workouts) // Already styled inside
                            }
                            
                            if viewModel.restingHeartRateData.isEmpty &&
                                viewModel.hrvData.isEmpty &&
                                viewModel.sleepData.isEmpty &&
                                viewModel.stepCountData.isEmpty &&
                                viewModel.workouts.isEmpty {
                                DashboardEmptyState()
                                    .cardStyle(for: .info)
                            }
                        }
                        .padding(.top, 10) // Spacing between header and first card
                    }
                } header: {
                    // PINNED HEADER: Time Period Picker
                    VStack {
                        Picker("Time Period", selection: $viewModel.selectedPeriod) {
                            ForEach(TimePeriod.allCases) { period in
                                Text(period.displayName).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .background(
                            // Glass background effect
                            Rectangle()
                                .fill(.regularMaterial)
                                .ignoresSafeArea(edges: .top)
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(TabBackgroundColor.dashboard(for: colorScheme))
        .navigationTitle("Dashboard")
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            Task { await viewModel.loadData() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.loadData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await viewModel.loadData() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataWindowChanged"))) { _ in
            // Force reload when data window changes
            Task {
                await viewModel.loadData()
            }
        }
    }
}


struct RestingHeartRateCard: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    var averageHR: Double {
        guard !data.isEmpty else { return 0 }
        return data.map { $0.value }.reduce(0, +) / Double(data.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Resting Heart Rate")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(Int(averageHR))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                    Text("avg bpm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Chart
            Chart(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(.red.gradient)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))
                
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red.opacity(0.3), .red.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 200)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .stride(by: period.xAxisStride.component, count: period.xAxisStride.count)) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            switch period {
                            case .week:
                                Text(date, format: .dateTime.weekday(.abbreviated))
                            case .month, .quarter:
                                Text(date, format: .dateTime.month(.abbreviated).day())
                            case .sixMonths, .year:
                                Text(date, format: .dateTime.month(.abbreviated))
                            case .all:
                                Text(date, format: .dateTime.year())
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.caption2)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.gray.opacity(0.2))
                }
            }
        }
        .padding(20)
    }
}

struct ErrorView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            Text("Error")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct SleepCard: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    var averageSleep: Double {
        guard !data.isEmpty else { return 0 }
        return data.map { $0.value }.reduce(0, +) / Double(data.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Sleep Duration")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(String(format: "%.1f", averageSleep))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("avg hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Chart
            Chart(data) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Hours", point.value)
                )
                .foregroundStyle(.blue.gradient)
                
                RuleMark(y: .value("Target", 7.5))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("7.5h goal")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
            }
            .frame(height: 200)
            .chartYScale(domain: 0...10)
            .chartXAxis {
                AxisMarks(values: .stride(by: period.xAxisStride.component, count: period.xAxisStride.count)) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            switch period {
                            case .week:
                                Text(date, format: .dateTime.weekday(.abbreviated))
                            case .month, .quarter:
                                Text(date, format: .dateTime.month(.abbreviated).day())
                            case .sixMonths, .year:
                                Text(date, format: .dateTime.month(.abbreviated))
                            case .all:
                                Text(date, format: .dateTime.year())
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}

struct StepCountCard: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    var totalSteps: Double {
        data.map { $0.value }.reduce(0, +)
    }
    
    var averageSteps: Double {
        guard !data.isEmpty else { return 0 }
        return totalSteps / Double(data.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Step Count")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(Int(averageSteps).formatted())")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("avg steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Chart
            Chart(data) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Steps", point.value)
                )
                .foregroundStyle(.orange.gradient)
                
                RuleMark(y: .value("Goal", 7000))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("7k goal")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
            }
            .frame(height: 200)
            .chartYScale(domain: 0...20000)
            .chartXAxis {
                AxisMarks(values: .stride(by: period.xAxisStride.component, count: period.xAxisStride.count)) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            switch period {
                            case .week:
                                Text(date, format: .dateTime.weekday(.abbreviated))
                            case .month, .quarter:
                                Text(date, format: .dateTime.month(.abbreviated).day())
                            case .sixMonths, .year:
                                Text(date, format: .dateTime.month(.abbreviated))
                            case .all:
                                Text(date, format: .dateTime.year())
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct WorkoutSummaryCard: View {
    let workouts: [WorkoutData]
    let period: TimePeriod
    
    var totalWorkouts: Int {
        workouts.count
    }
    
    // Calculate counts by type
    var countsByType: [(name: String, count: Int, icon: String)] {
        let grouped = Dictionary(grouping: workouts, by: { $0.workoutName })
        return grouped.map { (key, value) in
            (name: key, count: value.count, icon: value.first?.iconName ?? "figure.run")
        }.sorted { $0.count > $1.count }.prefix(3).map { $0 } // Top 3 types
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Workouts")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(totalWorkouts) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            //  Breakdown by Type (instead of Time/Calories)
            if !countsByType.isEmpty {
                HStack(spacing: 12) {
                    ForEach(countsByType, id: \.name) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.caption2)
                            Text("\(item.count) \(item.name)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            
            Divider()
            
            // Recent Workouts Header + See All Button
            HStack {
                Text("Recent Workouts")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                NavigationLink {
                    UnifiedWorkoutsView()
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            // Workout list (Top 3 only)
            let recent = workouts.sorted { $0.startDate > $1.startDate }.prefix(3)
            
            if recent.isEmpty {
                Text("No workouts found.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    ForEach(recent) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
            }
        }
        .padding()
        .cardStyle(for: .workouts)
    }
}

struct StatBox: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkoutRow: View {
    let workout: WorkoutData
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workout.iconName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(.orange.gradient)
                )
            
            // Workout info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(workout.workoutName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Source badge
                    HStack(spacing: 3) {
                        Image(systemName: workout.source.iconName)
                            .font(.system(size: 8))
                        Text(workout.source.rawValue)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(sourceColor(for: workout.source).opacity(0.15))
                    )
                    .foregroundStyle(sourceColor(for: workout.source))
                }
                
                Text(workout.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Stats
            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.formattedDuration)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Show power if available, otherwise show distance or calories
                Text(workout.secondaryMetric)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func sourceColor(for source: WorkoutSource) -> Color {
        switch source {
        case .appleWatch: return .blue
        case .strava: return .orange
        case .other: return .gray
        }
    }
}

struct WeightCard: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    var averageWeight: Double {
        guard !data.isEmpty else { return 0 }
        let total = data.map { $0.value }.reduce(0, +)
        return total / Double(data.count)
    }
    
    // Trend: Last recorded weight vs First recorded weight in period
    var trend: Double {
        guard let first = data.first?.value, let last = data.last?.value else { return 0 }
        return last - first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Body Weight")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(String(format: "%.1f", averageWeight))
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("avg lbs") // Label changed
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Optional: Show trend below average
                    if abs(trend) >= 0.1 {
                        HStack(spacing: 2) {
                            Image(systemName: trend < 0 ? "arrow.down" : "arrow.up")
                            Text(String(format: "%.1f lbs", abs(trend)))
                        }
                        .font(.caption2)
                        .foregroundStyle(trend < 0 ? .green : .red) // Green if weight lost, Red if gained
                        .padding(.top, 1)
                    }
                }
            }
            
            // Chart
            if data.isEmpty {
                Text("No weight data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(.purple.gradient)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    
                    // Show Average Line
                    RuleMark(y: .value("Average", averageWeight))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.purple.opacity(0.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .purple.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                // Smart Scale: Zoom to data range, but give 5lb padding
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .stride(by: period.xAxisStride.component, count: period.xAxisStride.count)) { value in
                        AxisGridLine()
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                switch period {
                                case .week:
                                    Text(date, format: .dateTime.weekday(.abbreviated))
                                case .month, .quarter:
                                    Text(date, format: .dateTime.month(.abbreviated).day())
                                case .sixMonths, .year:
                                    Text(date, format: .dateTime.month(.abbreviated))
                                case .all:
                                    Text(date, format: .dateTime.year())
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle(for: .nutrition) // Reuse an existing style or make a new one
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}

