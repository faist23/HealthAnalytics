//
//  SleepStagesChart.swift
//  HealthAnalytics
//

import SwiftUI
import Charts

struct SleepStagesChart: View {
    @ObservedObject var viewModel: SleepViewModel
    
    @Environment(\.colorScheme) var colorScheme
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Architecture")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.error)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else if viewModel.sleepStages.isEmpty {
                Text("No detailed sleep stage data available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(viewModel.sleepStages) { stage in
                        BarMark(
                            xStart: .value("Start", stage.startDate),
                            xEnd: .value("End", stage.endDate),
                            y: .value("Stage", stage.stage)
                        )
                        .foregroundStyle(colorForStage(stage.stage))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: ["Deep", "Core/Light", "REM", "Awake"]) { value in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .frame(height: 250)
                
                // Stage Summary
                HStack {
                    VStack(alignment: .leading) {
                        Text("Total Sleep")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.totalSleepString)
                            .font(.title3.bold())
                            .foregroundStyle(AppColors.sleep)
                    }
                }
                .padding(.top, 8)
            }
            } // Close VStack
        } // Close Button
        .buttonStyle(.plain)
        .padding()
        .solidCard()
        .sheet(isPresented: $showDetail) {
            MetricConditionDetailView(config: MetricDisplayConfig(
                id: "sleep_stages",
                title: "Sleep Architecture",
                icon: "moon.zzz.fill",
                currentValueFormatted: viewModel.totalSleepString,
                status: .good, // Real logic would compare to baseline
                citation: nil,
                thresholdBarValue: nil,
                conditionReasoning: "Your sleep is broken down into REM, Deep, and Core (Light) sleep. REM is crucial for mental recovery and memory consolidation, while Deep sleep is essential for physical repair.",
                guidanceText: "Aim for at least 1.5 - 2 hours of Deep sleep and 1.5 - 2 hours of REM sleep. Limit alcohol and caffeine before bed to improve your sleep architecture.",
                detailedInsight: nil
            ))
        }
        .task {
            if viewModel.sleepStages.isEmpty {
                await viewModel.fetchLastNightSleepStages()
            }
        }
    } // Close body
    
    private func colorForStage(_ stage: String) -> Color {
        switch stage {
        case "Deep":
            return AppColors.sleep.opacity(1.0)
        case "Core/Light":
            return AppColors.sleep.opacity(0.6)
        case "REM":
            return AppColors.sleep.opacity(0.3)
        case "Awake":
            return AppColors.steps.opacity(0.5)
        default:
            return .gray
        }
    }
}
