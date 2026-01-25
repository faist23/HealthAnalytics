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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    if viewModel.isLoading {
                        ProgressView("Loading health data...")
                            .padding()
                    } else if let error = viewModel.errorMessage {
                        ErrorView(message: error)
                    } else if viewModel.restingHeartRateData.isEmpty {
                        EmptyStateView()
                    } else {
                        // Resting Heart Rate
                        if !viewModel.restingHeartRateData.isEmpty {
                            RestingHeartRateCard(data: viewModel.restingHeartRateData)
                        }
                        
                        // HRV
                        if !viewModel.hrvData.isEmpty {
                            HRVCard(data: viewModel.hrvData)
                        }
                        
                        // Sleep
                        if !viewModel.sleepData.isEmpty {
                            SleepCard(data: viewModel.sleepData)
                        }
                        
                        // Steps
                        if !viewModel.stepCountData.isEmpty {
                            StepCountCard(data: viewModel.stepCountData)
                        }
                        
                        // Show empty state only if ALL data is empty
                        if viewModel.restingHeartRateData.isEmpty &&
                            viewModel.hrvData.isEmpty &&
                            viewModel.sleepData.isEmpty &&
                            viewModel.stepCountData.isEmpty {
                            EmptyStateView()
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
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
                    Text("Last 7 Days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(Int(averageHR))")
                        .font(.title)
                        .fontWeight(.bold)
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
                
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(.red.gradient.opacity(0.1))
                .interpolationMethod(.catmullRom)
                
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(.red)
            }
            .frame(height: 200)
            .chartYScale(domain: .automatic(includesZero: false))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                    Text("Last 7 Days")
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
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SleepCard: View {
    let data: [HealthDataPoint]
    
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
                    Text("Last 7 Days")
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
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
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

struct StepCountCard: View {
    let data: [HealthDataPoint]
    
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
                    Text("Last 7 Days")
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
            .chartYScale(domain: 0...15000)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
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


#Preview {
    ContentView()
}
