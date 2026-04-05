//
//  RecoveryTabView.swift
//  HealthAnalytics
//

import SwiftUI
import SwiftData

struct RecoveryTabView: View {
    @StateObject private var viewModel = ReadinessViewModel()
    @State private var isFirstLoad = true
    @State private var showBreakdown = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var syncManager = SyncManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05) // Dark Whoop-like background
                    .ignoresSafeArea()
                
                if syncManager.isBackfillingHistory {
                    BackfillProgressView(
                        progress: syncManager.backfillProgress,
                        message: syncManager.syncProgress
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if let error = viewModel.errorMessage {
                                ErrorView(message: error)
                                    .cardStyle(for: .error)
                            }
                            
                            if !viewModel.isLoading && !isFirstLoad {
                                if let readiness = viewModel.readinessScore {
                                    let levelLabel: String = {
                                        if readiness.score >= 67 { return "OPTIMAL" }
                                        if readiness.score >= 34 { return "MONITORING" }
                                        return "REST"
                                    }()
                                    
                                    // 1. Whoop Circular Gauge
                                    CircularGauge(
                                        title: "RECOVERY",
                                        value: "\(readiness.score)%",
                                        subtitle: levelLabel,
                                        progress: Double(readiness.score) / 100.0,
                                        color: scoreColor(for: readiness.score)
                                    )
                                    
                                    // 2. Metric List (using Breakdown scores)
                                    MetricList {
                                        GaugeMetricRow(
                                            icon: "waveform.path.ecg",
                                            title: "RECOVERY SCORE",
                                            value: "\(readiness.breakdown.recoveryScore)/40",
                                            trendIcon: "arrowtriangle.up.fill",
                                            trendColor: .green
                                        )
                                        Divider().background(Color.white.opacity(0.1))
                                        GaugeMetricRow(
                                            icon: "figure.run",
                                            title: "FITNESS BASE",
                                            value: "\(readiness.breakdown.fitnessScore)/30",
                                            trendIcon: "arrowtriangle.up.fill",
                                            trendColor: .green
                                        )
                                        Divider().background(Color.white.opacity(0.1))
                                        GaugeMetricRow(
                                            icon: "battery.50",
                                            title: "FATIGUE MANAGEMENT",
                                            value: "\(readiness.breakdown.fatigueScore)/30",
                                            trendIcon: "circle.fill",
                                            trendColor: .gray
                                        )
                                    }
                                    .padding(.horizontal)
                                    
                                    // 3. Insight Box
                                    InsightBox(
                                        text: readiness.recommendation,
                                        actionText: "BREAK DOWN MY RECOVERY"
                                    ) {
                                        showBreakdown = true
                                    }
                                    .padding(.horizontal)
                                    
                                    // Keep Energy Bank Chart
                                    EnergyBankChart(
                                        intraDay: viewModel.intraDayReadiness,
                                        baselineScore: readiness.score,
                                        todayWorkouts: viewModel.todayWorkouts
                                    )
                                    
                                } else {
                                    ReadinessEmptyState()
                                        .cardStyle(for: .info)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .scrollContentBackground(.hidden)
                }
                
                if viewModel.isLoading || isFirstLoad {
                    LoadingOverlay(message: "Analyzing your recovery...")
                }
            }
            .navigationTitle("TODAY")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.modelContainer == nil {
                    viewModel.configure(container: modelContext.container)
                }
                await viewModel.analyze(modelContext: modelContext)
                isFirstLoad = false
            }
            .refreshable {
                await viewModel.analyze(modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showBreakdown) {
            if let breakdown = viewModel.readinessScore?.breakdown {
                NavigationStack {
                    ScrollView {
                        ScoreBreakdownCard(breakdown: breakdown)
                    }
                    .navigationTitle("Recovery Breakdown")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showBreakdown = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
    
    private func scoreColor(for score: Int) -> Color {
        if score >= 67 { return .green }
        if score >= 34 { return .yellow }
        return .red
    }
}

#Preview {
    RecoveryTabView()
}
