//
//  ContentView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Time period picker
                Picker("Time Period", selection: $viewModel.selectedPeriod) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: viewModel.selectedPeriod) { oldValue, newValue in
                    Task {
                        await viewModel.loadData()
                    }
                }
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        if viewModel.isLoading {
                            ProgressView("Loading health data...")
                                .padding()
                        } else if let error = viewModel.errorMessage {
                            ErrorView(message: error)
                        } else {
                            // Resting Heart Rate
                            if !viewModel.restingHeartRateData.isEmpty {
                                RestingHeartRateCard(
                                    data: viewModel.restingHeartRateData,
                                    period: viewModel.selectedPeriod
                                )
                            }
                            
                            // HRV
                            if !viewModel.hrvData.isEmpty {
                                HRVCard(
                                    data: viewModel.hrvData,
                                    period: viewModel.selectedPeriod
                                )
                            }
                            
                            // Sleep
                            if !viewModel.sleepData.isEmpty {
                                SleepCard(
                                    data: viewModel.sleepData,
                                    period: viewModel.selectedPeriod
                                )
                            }
                            
                            // Steps
                            if !viewModel.stepCountData.isEmpty {
                                StepCountCard(
                                    data: viewModel.stepCountData,
                                    period: viewModel.selectedPeriod
                                )
                            }
                            
                            // Workouts
                            if !viewModel.workouts.isEmpty {
                                WorkoutSummaryCard(
                                    workouts: viewModel.workouts,
                                    period: viewModel.selectedPeriod
                                )
                            }
                            
                            // Show empty state only if ALL data is empty
                            if viewModel.restingHeartRateData.isEmpty &&
                                viewModel.hrvData.isEmpty &&
                                viewModel.sleepData.isEmpty &&
                                viewModel.stepCountData.isEmpty &&
                                viewModel.workouts.isEmpty {
                                EmptyStateView()
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            .background(TabBackgroundColor.dashboard(for: colorScheme))
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
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
                AxisMarks { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor.secondarySystemGroupedBackground }))
                .shadow(color: .black.opacity(0.1), radius: 15, y: 8)
        )
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "heart.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Data Available")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Make sure you have resting heart rate data in the Health app")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
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

struct HRVCard: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    var averageHRV: Double {
        guard !data.isEmpty else { return 0 }
        return data.map { $0.value }.reduce(0, +) / Double(data.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Heart Rate Variability")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(Int(averageHRV))")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("avg ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Chart
            Chart(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value)
                )
                .foregroundStyle(.green.gradient)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value)
                )
                .foregroundStyle(.green.gradient.opacity(0.1))
                .interpolationMethod(.catmullRom)
                
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value)
                )
                .foregroundStyle(.green)
            }
            .frame(height: 200)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel(format: period == .week ? .dateTime.month().day() : .dateTime.month())
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor.secondarySystemGroupedBackground }))
                .shadow(color: .black.opacity(0.1), radius: 15, y: 8)
        )
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
                
                RuleMark(y: .value("Target", 7.0))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("7h goal")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
            }
            .frame(height: 200)
            .chartYScale(domain: 0...10)
            .chartXAxis {
                AxisMarks(values: .stride(by: period == .week ? .day : .day, count: period == .week ? 1 : period == .month ? 5 : 15)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: period == .week ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated))
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor.secondarySystemGroupedBackground }))
                .shadow(color: .black.opacity(0.1), radius: 15, y: 8)
        )
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
                
                RuleMark(y: .value("Goal", 10000))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("10k goal")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
            }
            .frame(height: 200)
            .chartYScale(domain: 0...20000)
            .chartXAxis {
                AxisMarks(values: .stride(by: period == .week ? .day : .day, count: period == .week ? 1 : period == .month ? 5 : 15)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: period == .week ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated))
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor.secondarySystemGroupedBackground }))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
        
    }
}

struct WorkoutSummaryCard: View {
    let workouts: [WorkoutData]
    let period: TimePeriod
    
    var totalWorkouts: Int {
        workouts.count
    }
    
    var totalDuration: TimeInterval {
        workouts.map { $0.duration }.reduce(0, +)
    }
    
    var totalCalories: Double {
        workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
    }
    
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Workouts")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(totalWorkouts) workouts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Summary stats
            HStack(spacing: 20) {
                StatBox(icon: "clock.fill", value: formattedTotalDuration, label: "Total Time")
                StatBox(icon: "flame.fill", value: "\(Int(totalCalories))", label: "Calories")
            }
            
            Divider()
            
            // Workout list
            VStack(spacing: 12) {
                ForEach(workouts.prefix(5)) { workout in
                    WorkoutRow(workout: workout)
                }
            }
            
            if workouts.count > 5 {
                Text("+ \(workouts.count - 5) more workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
            }
        }
        .padding()
        .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor.secondarySystemGroupedBackground }))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
        
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
                if let power = workout.formattedPower {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text(power)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else if let distance = workout.formattedDistance {
                    Text(distance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(workout.formattedCalories)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

// MARK: - Modern Card Style

struct ModernCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor.secondarySystemGroupedBackground }))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 20, y: 10)
            )
    }
}

extension View {
    func modernCard() -> some View {
        modifier(ModernCardStyle())
    }
}

#Preview {
    ContentView()
}
