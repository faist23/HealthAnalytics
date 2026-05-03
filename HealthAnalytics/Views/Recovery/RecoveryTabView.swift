//
//  RecoveryTabView.swift
//  HealthAnalytics
//

import SwiftUI
import SwiftData

struct RecoveryTabView: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var coordinator: TabCoordinator
    @StateObject private var viewModel = ReadinessViewModel()
    @State private var isFirstLoad = true
    @State private var showBreakdown = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var syncManager = SyncManager.shared
    @Query private var detectedPatterns: [TrainingPattern]

    private var topActivePattern: TrainingPattern? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return detectedPatterns
            .filter { $0.detectedAt >= cutoff }
            .min { PatternType.displayPriority($0.patternType) < PatternType.displayPriority($1.patternType) }
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
                        VStack(spacing: .spacingLg) {
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
                                        actionText: "BREAK DOWN MY RECOVERY",
                                        action: { showBreakdown = true },
                                        navigationText: topActivePattern.map { "See \($0.patternType.displayName) in Intelligence →" },
                                        navigationAction: topActivePattern.map { pattern in
                                            { coordinator.navigate(to: TabCoordinator.intelligenceTab, scrollTo: pattern.patternType) }
                                        }
                                    )
                                    .padding(.horizontal)
                                    
                                    // Keep Energy Bank Chart
                                    // priorDayFatigueImpact: fatigueScore of 30 = no debt;
                                    // every point below 30 represents carry-forward strain.
                                    EnergyBankChart(
                                        intraDay: viewModel.intraDayReadiness,
                                        baselineScore: readiness.score,
                                        priorDayFatigueImpact: Double(30 - readiness.breakdown.fatigueScore),
                                        todayWorkouts: viewModel.todayWorkouts,
                                        todayStepExcessTSS: viewModel.todayStepExcessTSS,
                                        overnightRecoveryMultiplier: viewModel.overnightRecoveryMultiplier
                                    )

                                    // 7-Day Readiness Forecast
                                    ReadinessForecastChart()

                                    // 14-Day Signature — back-to-back crash pattern
                                    TrainingSignatureCard()

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task {
                if viewModel.modelContainer == nil {
                    viewModel.configure(container: modelContext.container)
                }
                await viewModel.analyze(modelContext: modelContext)
                isFirstLoad = false
                // TrainingSignatureCard lives here but runPatternAnalysis was only wired
                // to InsightsView (a sheet). Drive it from the tab that shows the card.
                // force: true bypasses the 7-day staleness gate on every launch so the
                // card reflects current StoredDailyScore data without waiting a week.
                await ReadinessRepository.shared.runPatternAnalysis(container: modelContext.container, force: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataSyncCompleted"))) { _ in
                // Re-analyze after sync so today's workouts are always current on first open.
                // Without this, the initial .task races with performSmartSync() and wins — reading
                // SwiftData before today's workout is written, then never refreshing.
                Task { await viewModel.analyze(modelContext: modelContext) }
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
        if score >= 67 { return Color.statusOptimal }
        if score >= 34 { return Color.statusMonitoring }
        return Color.statusRest
    }
}

#Preview {
    RecoveryTabView(showSettings: .constant(false))
}
