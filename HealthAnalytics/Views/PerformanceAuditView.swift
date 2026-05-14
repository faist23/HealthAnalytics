//
//  PerformanceAuditView.swift
//  HealthAnalytics
//

import SwiftUI
import HealthKit
import SwiftData
import Combine

@MainActor
class PerformanceAuditViewModel: ObservableObject {
    @Published var standoutWorkouts: [CorrelationEngine.StandoutWorkoutInsight] = []
    @Published var isLoading = false
    
    func analyzePerformances(modelContext: ModelContext) async {
        isLoading = true
        
        let hkManager = HealthKitManager.shared
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .month, value: -3, to: endDate)! // Last 90 days
        
        do {
            let workouts = try await hkManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            let sleepData = try await hkManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            let hrvData = try await hkManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            
            let dailyScores = try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())
            var scoreMap: [Date: Int] = [:]
            for score in dailyScores ?? [] {
                scoreMap[calendar.startOfDay(for: score.date)] = score.readinessScore
            }
            
            let engine = CorrelationEngine()
            let insights = engine.analyzeStandoutWorkouts(
                workouts: workouts,
                sleepData: sleepData,
                hrvData: hrvData,
                dailyReadinessScores: scoreMap
            )
            
            self.standoutWorkouts = insights
        } catch {
            print("Failed to analyze standout workouts: \(error)")
        }
        
        isLoading = false
    }
}

struct PerformanceAuditView: View {
    @StateObject private var viewModel = PerformanceAuditViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            if viewModel.isLoading {
                LoadingOverlay(message: "Analyzing 90-day performance history...")
            } else if viewModel.standoutWorkouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiary)
                    Text("No Standout Performances")
                        .font(.headline)
                    Text("We need at least 5 workouts of the same type to establish a baseline before we can detect your peak performances.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peak Performances")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Workouts where you performed significantly above your personal baseline, and the 72-hour patterns that preceded them.")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top)

                        ForEach(viewModel.standoutWorkouts) { insight in
                            StandoutWorkoutCard(insight: insight)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Performance Audit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.analyzePerformances(modelContext: modelContext)
        }
    }
}

struct StandoutWorkoutCard: View {
    let insight: CorrelationEngine.StandoutWorkoutInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Workout Name & Date
            HStack {
                Image(systemName: workoutIcon(for: insight.workout.workoutType))
                    .font(.title2)
                    .foregroundStyle(Color.accent)
                
                VStack(alignment: .leading) {
                    Text(insight.workout.workoutName)
                        .font(.headline)
                    Text(insight.workout.startDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                // Badge
                Text("+\(String(format: "%.0f", insight.performanceIncreasePercent))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.statusOptimal.opacity(0.2))
                    .foregroundStyle(Color.statusOptimal)
                    .clipShape(Capsule())
            }
            
            Divider()
            
            // Contributors List
            VStack(alignment: .leading, spacing: 8) {
                Text("Why did you perform better?")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(insight.identifiedContributors, id: \.self) { contributor in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusOptimal)
                            .font(.system(size: 14))
                            .padding(.top, 2)
                        
                        Text(contributor)
                            .font(.subheadline)
                    }
                }
            }
            .padding(12)
            .background(Color.statusOptimal.opacity(0.05))
            .cornerRadius(8)
            
            // Raw Metrics
            HStack(spacing: 20) {
                MetricMiniBox(title: "Performance", value: String(format: "%.1f", insight.performanceMetric), unit: unit(for: insight.workout.workoutType))
                MetricMiniBox(title: "Your Avg", value: String(format: "%.1f", insight.baselinePerformance), unit: unit(for: insight.workout.workoutType))
                MetricMiniBox(title: "72h HRV", value: String(format: "%+%.0f%%", insight.hrvTrend), unit: "vs avg")
            }
        }
        .padding()
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    
    private func workoutIcon(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        default: return "figure.mixed.cardio"
        }
    }
    
    private func unit(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running, .walking: return "mph"
        case .cycling: return "watts"
        default: return "metric"
        }
    }
}

struct MetricMiniBox: View {
    let title: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
