//
//  SleepTabView.swift
//  HealthAnalytics
//

import SwiftUI

struct SleepTabView: View {
    @StateObject private var viewModel = SleepViewModel()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05) // Dark background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        if !viewModel.isLoading && !viewModel.sleepStages.isEmpty {
                            let neededSleep = 8.0
                            let sleepPerformance = min(viewModel.totalSleepHours / neededSleep, 1.0)
                            let sleepPercentage = Int(sleepPerformance * 100)
                            
                            // 1. Circular Gauge
                            CircularGauge(
                                title: "SLEEP",
                                value: "\(sleepPercentage)%",
                                subtitle: "PERFORMANCE",
                                progress: sleepPerformance,
                                color: sleepPercentage >= 80 ? .blue : (sleepPercentage >= 60 ? .yellow : .red)
                            )
                            
                            // 2. Metric List
                            MetricList {
                                GaugeMetricRow(
                                    icon: "moon.zzz.fill",
                                    title: "HOURS OF SLEEP",
                                    value: viewModel.totalSleepString,
                                    trendIcon: "arrowtriangle.up.fill",
                                    trendColor: .green
                                )
                                Divider().background(Color.white.opacity(0.1))
                                GaugeMetricRow(
                                    icon: "bed.double.fill",
                                    title: "NEEDED SLEEP",
                                    value: "8h 0m",
                                    trendIcon: "circle.fill",
                                    trendColor: .gray
                                )
                            }
                            .padding(.horizontal)
                            
                            // 3. Insight Box (Static coaching, no sheet)
                            InsightBox(
                                text: sleepPercentage >= 80 ? "Your Sleep Performance is optimal. You got enough rest to fully recover from yesterday's strain." : "Your Sleep Performance is below your needed sleep. Consider an earlier bedtime tonight to catch up on sleep debt.",
                                actionText: nil
                            )
                            .padding(.horizontal)
                        }
                        
                        // 4. Sleep History (Now directly on page)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SLEEP HISTORY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1)
                                .padding(.leading, 4)
                            
                            DetailedSleepChart(data: viewModel.sleepHistory, period: .month)
                                .padding()
                                .background(Color(white: 0.12))
                                .clipShape(RoundedRectangle(cornerRadius: .radiusMd))
                        }
                        .padding(.horizontal)
                        
                        // 5. Sleep Architecture (Stacked visual)
                        SleepStagesChart(viewModel: viewModel)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .scrollContentBackground(.hidden)
                
                if viewModel.isLoading {
                    LoadingOverlay(message: "Analyzing your sleep...")
                }
            }
            .navigationTitle("TODAY")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.fetchSleepData()
            }
            .refreshable {
                await viewModel.fetchSleepData()
            }
        }
    }
}

#Preview {
    SleepTabView()
}
