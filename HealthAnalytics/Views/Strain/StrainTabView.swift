//
//  StrainTabView.swift
//  HealthAnalytics
//

import SwiftUI
import SwiftData
import HealthKit

struct StrainTabView: View {
    @StateObject private var viewModel = ReadinessViewModel()
    @State private var isFirstLoad = true
    @State private var showStrainDetails = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var syncManager = SyncManager.shared

    private var maxHR: Double {
        220.0 - Double(HealthKitManager.shared.getUserAge() ?? 35)
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private var estimatedZ1_3: TimeInterval {
        var total: TimeInterval = 0
        for workout in viewModel.todayWorkouts {
            let hr = workout.averageHeartRate ?? (maxHR * 0.7)
            let hrPercentage = hr / maxHR
            if hrPercentage < 0.8 {
                total += workout.duration
            }
        }
        return total
    }

    private var estimatedZ4_5: TimeInterval {
        var total: TimeInterval = 0
        for workout in viewModel.todayWorkouts {
            let hr = workout.averageHeartRate ?? (maxHR * 0.7)
            let hrPercentage = hr / maxHR
            if hrPercentage >= 0.8 {
                total += workout.duration
            }
        }
        return total
    }
    
    private var strengthTime: TimeInterval {
        viewModel.todayWorkouts
            .filter { 
                $0.workoutType == .traditionalStrengthTraining || 
                $0.workoutType == .functionalStrengthTraining ||
                $0.workoutType == .coreTraining ||
                $0.workoutType == .flexibility ||
                $0.workoutType == .crossTraining ||
                $0.workoutType == .highIntensityIntervalTraining ||
                $0.workoutName.lowercased().contains("strength") ||
                $0.workoutName.lowercased().contains("weight") ||
                $0.workoutName.lowercased().contains("lift") ||
                $0.workoutName.lowercased().contains("gym") ||
                $0.workoutName.lowercased().contains("dumbbell")
            }
            .reduce(0) { $0 + $1.duration }
    }

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
                                if let assessment = viewModel.readinessAssessment {
                                    let strainValue = min(assessment.acwr * 10.0, 21.0)
                                    let strainLabel: String = {
                                        if strainValue < 10 { return "LIGHT" }
                                        if strainValue < 14 { return "MODERATE" }
                                        if strainValue < 18 { return "STRENUOUS" }
                                        return "ALL-OUT"
                                    }()
                                    
                                    // 1. Circular Gauge
                                    VStack(spacing: 8) {
                                        CircularGauge(
                                            title: "STRAIN",
                                            value: String(format: "%.1f", strainValue),
                                            subtitle: strainLabel,
                                            progress: strainValue / 21.0,
                                            color: .blue
                                        )
                                        
                                        Text("Range: 0.0 — 21.0")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .opacity(0.8)
                                    }
                                    .padding(.bottom, 10)
                                    
                                    // 2. Metric List
                                    MetricList {
                                        GaugeMetricRow(
                                            icon: "heart.circle",
                                            title: "HEART RATE ZONES 1-3",
                                            value: formatDuration(estimatedZ1_3),
                                            trendIcon: "arrowtriangle.up.fill",
                                            trendColor: .green
                                        )
                                        Divider().background(Color.white.opacity(0.1))
                                        GaugeMetricRow(
                                            icon: "heart.circle.fill",
                                            title: "HEART RATE ZONES 4-5",
                                            value: formatDuration(estimatedZ4_5),
                                            trendIcon: "arrowtriangle.down.fill",
                                            trendColor: .green
                                        )
                                        Divider().background(Color.white.opacity(0.1))
                                        GaugeMetricRow(
                                            icon: "dumbbell.fill",
                                            title: "STRENGTH ACTIVITY TIME",
                                            value: formatDuration(strengthTime),
                                            trendIcon: "arrowtriangle.down.fill",
                                            trendColor: .yellow
                                        )
                                    }
                                    .padding(.horizontal)
                                    
                                    // 3. Scale Explanation Card
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("STRAIN SCALE")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                            .tracking(1)
                                        
                                        VStack(spacing: 1) {
                                            ScaleRow(label: "0 — 9", description: "Light", color: .blue.opacity(0.6))
                                            ScaleRow(label: "10 — 13", description: "Moderate", color: .blue.opacity(0.8))
                                            ScaleRow(label: "14 — 17", description: "Strenuous", color: .blue)
                                            ScaleRow(label: "18 — 21", description: "All-Out", color: .indigo)
                                        }
                                        .background(Color(white: 0.1).opacity(0.8))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
                                    }
                                    .padding(.horizontal)
                                    
                                    // 4. Insight Box
                                    let defaultRecommendation = "Your current strain is in the strenuous zone. This level of activity requires significant cardiovascular adaptation."
                                    InsightBox(
                                        text: viewModel.dailyRecommendation?.guidance ?? defaultRecommendation,
                                        actionText: "EXPLORE MY STRAIN"
                                    ) {
                                        showStrainDetails = true
                                    }
                                    .padding(.horizontal)
                                    
                                }
                                
                                // Balance Plot
                                StrainRecoveryBalancePlot(
                                    currentReadiness: viewModel.readinessScore?.score,
                                    currentACWR: viewModel.readinessAssessment?.acwr
                                )
                                
                                // TSS Chart
                                if !viewModel.dailyTSSData.isEmpty {
                                    TSSChartCard(
                                        dailyTSS: viewModel.dailyTSSData,
                                        period: viewModel.selectedPeriod
                                    )
                                    .cardStyle(for: .workouts)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .scrollContentBackground(.hidden)
                }
                
                if viewModel.isLoading || isFirstLoad {
                    LoadingOverlay(message: "Analyzing your strain...")
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
        .sheet(isPresented: $showStrainDetails) {
            if let assessment = viewModel.readinessAssessment, !viewModel.acwrTrend.isEmpty {
                NavigationStack {
                    ScrollView {
                        UnifiedTrainingLoadCard(
                            assessment: assessment,
                            trend: viewModel.acwrTrend,
                            summary: viewModel.trainingLoadSummary,
                            primaryActivity: viewModel.primaryActivity,
                            extendedData: viewModel.loadVisualization
                        )
                        .padding()
                    }
                    .navigationTitle("Strain Details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showStrainDetails = false }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }
}

#Preview {
    StrainTabView()
}

struct ScaleRow: View {
    let label: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)
            
            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 40, height: 4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
