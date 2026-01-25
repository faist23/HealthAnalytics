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
                        RestingHeartRateCard(data: viewModel.restingHeartRateData)
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

#Preview {
    ContentView()
}
