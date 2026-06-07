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
    @State private var maxHR: Double = 185.0   // seeded once in .task; updated via cardiovascularStrain
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var syncManager = SyncManager.shared
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private var granularZ1_3: TimeInterval {
        viewModel.cardiovascularStrain?.timeInZ1_3 ?? 0
    }

    private var granularZ4_5: TimeInterval {
        viewModel.cardiovascularStrain?.timeInZ4_5 ?? 0
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
            mainView
                .navigationTitle("TODAY")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .task {
                    if let cv = viewModel.cardiovascularStrain {
                        maxHR = cv.estimatedMaxHR
                    } else {
                        maxHR = 220.0 - Double(HealthKitManager.shared.getUserAge() ?? 35)
                    }
                    isFirstLoad = false
                }
                .onChange(of: viewModel.cardiovascularStrain) { _, cv in
                    if let cv { maxHR = cv.estimatedMaxHR }
                }
                .refreshable {
                    await SyncManager.shared.performSmartSync()
                    await ReadinessRepository.shared.refreshIfNecessary(modelContext: modelContext)
                }
        }
    }

    // MARK: - Sub-views (decomposed to avoid type-checker timeout)

    private var mainView: some View {
        ZStack {
            Color(white: 0.05)
                .ignoresSafeArea()

            if syncManager.isBackfillingHistory {
                BackfillProgressView(
                    progress: syncManager.backfillProgress,
                    message: syncManager.syncProgress
                )
            } else {
                ScrollView {
                    VStack(spacing: .spacingLg) {
                        if let error = viewModel.errorMessage {
                            ErrorView(message: error) {
                                Task {
                                    await SyncManager.shared.performSmartSync()
                                    await ReadinessRepository.shared.refreshIfNecessary(modelContext: modelContext)
                                }
                            }
                            .cardStyle(for: .error)
                        }

                        if !viewModel.isLoading && !isFirstLoad {
                            strainGauge
                            metricList
                            trainingLoadSection
                            strainScaleCard
                            insightSection
                            StrainRecoveryBalancePlot(
                                currentReadiness: viewModel.readinessScore?.score,
                                currentACWR: viewModel.readinessAssessment?.acwr
                            )
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
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Color.textSecondary)
            }
            .accessibilityLabel("Settings")
        }
    }

    @ViewBuilder
    private var strainGauge: some View {
        if let cvStrain = viewModel.cardiovascularStrain {
            VStack(spacing: .spacingSm) {
                CircularGauge(
                    title: "CARDIO LOAD",
                    value: String(format: "%.1f", cvStrain.strain),
                    subtitle: CardiovascularStrainService.label(for: cvStrain.strain),
                    progress: cvStrain.strain / 21.0,
                    color: CardiovascularStrainService.color(for: cvStrain.strain)
                )
                if cvStrain.dataQuality == .insufficient {
                    Text("Wear your Apple Watch longer for an accurate score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Text("Range: 0.0 — 21.0")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
            }
            .padding(.bottom, .spacingSm)
        } else {
            // No fabricated ACWR-derived strain. Cardio load needs raw HR samples
            // from the watch; without them we say so plainly.
            VStack(spacing: .spacingSm) {
                Image(systemName: "applewatch")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Cardio load needs watch data")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Wear your Apple Watch during workouts so we can read heart rate samples. Your load score will appear here once we have enough data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical, .spacingMd)
        }
    }

    private var metricList: some View {
        MetricList {
            GaugeMetricRow(
                icon: "heart.circle",
                title: "HEART RATE ZONES 1-3",
                value: formatDuration(granularZ1_3),
                trendIcon: "arrowtriangle.up.fill",
                trendColor: .green
            )
            Divider().background(Color.white.opacity(0.1))
            GaugeMetricRow(
                icon: "heart.circle.fill",
                title: "HEART RATE ZONES 4-5",
                value: formatDuration(granularZ4_5),
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
            Divider().background(Color.white.opacity(0.1))
            GaugeMetricRow(
                icon: "figure.walk",
                title: "TODAY'S STEPS",
                value: viewModel.todaySteps > 0 ? "\(viewModel.todaySteps.formatted())" : "--",
                trendIcon: "arrowtriangle.up.fill",
                trendColor: .green
            )
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var trainingLoadSection: some View {
        if let assessment = viewModel.readinessAssessment {
            VStack(alignment: .leading, spacing: .spacingSm) {
                Text("TRAINING LOAD")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.horizontal)
                ACWRTrendCard(
                    trend: viewModel.acwrTrend,
                    currentAssessment: assessment,
                    primaryActivity: viewModel.primaryActivity
                )
                .padding(.horizontal)
                if viewModel.loadVisualization != nil || viewModel.trainingLoadSummary != nil {
                    NavigationLink {
                        LoadDetailsView(
                            assessment: assessment,
                            trend: viewModel.acwrTrend,
                            summary: viewModel.trainingLoadSummary,
                            primaryActivity: viewModel.primaryActivity,
                            extendedData: viewModel.loadVisualization
                        )
                    } label: {
                        HStack(spacing: .spacingXs) {
                            Text("More load detail")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    private var strainScaleCard: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            Text("CARDIO LOAD SCALE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(1.0)
            VStack(spacing: 1) {
                ScaleRow(label: "0 – 6.9",   description: "Light",     color: Color.statusOptimal)
                ScaleRow(label: "7 – 12.9",  description: "Moderate",  color: Color.statusMonitoring)
                ScaleRow(label: "13 – 17.9", description: "Strenuous", color: Color.statusWarning)
                ScaleRow(label: "18 – 21",   description: "All-Out",   color: Color.statusAllOut)
            }
            .background(Color(white: 0.1).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: .radiusSm))
            .overlay(RoundedRectangle(cornerRadius: .radiusSm).stroke(Color.white.opacity(0.05), lineWidth: 1))

            if let cv = viewModel.cardiovascularStrain {
                calibrationRows(cv: cv)
            }
        }
        .padding(.spacingMd)
        .background(Color(white: 0.1).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: .radiusMd))
        .padding(.horizontal)
    }

    private func calibrationRows(cv: CardiovascularStrainService.Result) -> some View {
        VStack(alignment: .leading, spacing: .spacingXs) {
            Divider().background(Color.white.opacity(0.08))
            Text("CALIBRATION")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(spacing: .spacingLg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal Max HR").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(cv.estimatedMaxHR)) bpm")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resting HR").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(cv.restingHRUsed)) bpm")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("HR Samples").font(.caption2).foregroundStyle(.secondary)
                    Text("\(cv.sampleCount)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var insightSection: some View {
        let defaultRecommendation = "Your current cardio load is in the strenuous zone. This level of activity requires significant cardiovascular adaptation."
        return InsightBox(
            text: viewModel.dailyRecommendation?.guidance ?? defaultRecommendation,
            actionText: nil
        )
        .padding(.horizontal)
    }
}

/// Push-navigation destination that hosts the legacy UnifiedTrainingLoadCard.
/// Reachable from the "More load detail" link below the inline ACWR chart.
private struct LoadDetailsView: View {
    let assessment: PredictiveReadinessService.ReadinessAssessment
    let trend: [ACWRDataPoint]
    let summary: TrainingLoadCalculator.TrainingLoadSummary?
    let primaryActivity: String
    let extendedData: TrainingLoadVisualizationService.LoadVisualizationData?

    var body: some View {
        ScrollView {
            UnifiedTrainingLoadCard(
                assessment: assessment,
                trend: trend,
                summary: summary,
                primaryActivity: primaryActivity,
                extendedData: extendedData
            )
            .padding()
        }
        .navigationTitle("Load Details")
        .navigationBarTitleDisplayMode(.inline)
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
        .padding(.horizontal, .spacingMd)
    }
}
