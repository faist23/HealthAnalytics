//
//  StrainRecoveryBalancePlot.swift
//  HealthAnalytics
//

import SwiftUI
import Charts

struct StrainRecoveryBalancePlot: View {
    let currentReadiness: Int?
    let currentACWR: Double?
    
    @Environment(\.colorScheme) var colorScheme
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
            Text("Strain vs. Recovery Balance")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if let readiness = currentReadiness, let acwr = currentACWR {
                Chart {
                    // Background Zones
                    // Optimal ACWR is 0.8 - 1.3 (GEMINI.md)
                    
                    // Optimal Zone
                    RectangleMark(
                        xStart: .value("Readiness Min", 40),
                        xEnd: .value("Readiness Max", 100),
                        yStart: .value("ACWR Min", 0.8),
                        yEnd: .value("ACWR Max", 1.3)
                    )
                    .foregroundStyle(AppColors.hrv.opacity(0.1))
                    .annotation(position: .overlay, alignment: .center) {
                        Text("Optimal")
                            .font(.caption2)
                            .foregroundStyle(AppColors.hrv)
                    }
                    
                    // Overreaching Zone
                    RectangleMark(
                        xStart: .value("Readiness Min", 0),
                        xEnd: .value("Readiness Max", 100),
                        yStart: .value("ACWR Min", 1.3),
                        yEnd: .value("ACWR Max", 2.0)
                    )
                    .foregroundStyle(AppColors.error.opacity(0.1))
                    .annotation(position: .overlay, alignment: .top) {
                        Text("Overreaching")
                            .font(.caption2)
                            .foregroundStyle(AppColors.error)
                            .padding(.top, 4)
                    }
                    
                    // Underreaching Zone
                    RectangleMark(
                        xStart: .value("Readiness Min", 0),
                        xEnd: .value("Readiness Max", 100),
                        yStart: .value("ACWR Min", 0.0),
                        yEnd: .value("ACWR Max", 0.8)
                    )
                    .foregroundStyle(AppColors.sleep.opacity(0.1))
                    .annotation(position: .overlay, alignment: .bottom) {
                        Text("Underreaching")
                            .font(.caption2)
                            .foregroundStyle(AppColors.sleep)
                            .padding(.bottom, 4)
                    }
                    
                    // Rest Zone (Low readiness, any ACWR but ideally should be low)
                    RectangleMark(
                        xStart: .value("Readiness Min", 0),
                        xEnd: .value("Readiness Max", 40),
                        yStart: .value("ACWR Min", 0.8),
                        yEnd: .value("ACWR Max", 1.3)
                    )
                    .foregroundStyle(AppColors.steps.opacity(0.1))
                    .annotation(position: .overlay, alignment: .center) {
                        Text("Rest Required")
                            .font(.caption2)
                            .foregroundStyle(AppColors.steps)
                    }
                    
                    // Current Point
                    PointMark(
                        x: .value("Recovery", readiness),
                        y: .value("Strain", acwr)
                    )
                    .symbolSize(200)
                    .foregroundStyle(.primary)
                    .annotation(position: .top) {
                        Text("Today")
                            .font(.caption.bold())
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [0, 20, 40, 60, 80, 100]) { value in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0.0, 0.5, 0.8, 1.3, 1.5, 2.0]) { value in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .chartXScale(domain: 0...100)
                .chartYScale(domain: 0...2.0)
                .frame(height: 250)
                
                // Summary text
                HStack {
                    VStack(alignment: .leading) {
                        Text("Recovery (Readiness)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(readiness)")
                            .font(.title3.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Strain (ACWR)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", acwr))
                            .font(.title3.bold())
                    }
                }
                .padding(.top, 8)
                
            } else {
                Text("Not enough data to plot Strain vs. Recovery balance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            }
            } // Close VStack
        } // Close Button
        .buttonStyle(.plain)
        .padding()
        .solidCard()
        .sheet(isPresented: $showDetail) {
            MetricConditionDetailView(config: MetricDisplayConfig(
                id: "strain_balance",
                title: "Strain vs. Recovery",
                icon: "flame.fill",
                currentValueFormatted: currentACWR != nil ? String(format: "%.2f", currentACWR!) : "--",
                status: (currentACWR ?? 0) >= 0.8 && (currentACWR ?? 0) <= 1.3 ? .good : .needsAttention,
                citation: nil,
                thresholdBarValue: nil,
                conditionReasoning: "Balancing your daily strain against your body's readiness is key to consistent progression and injury prevention.",
                guidanceText: "Aim to keep your dot in the 'Optimal' zone. If you are 'Overreaching', prioritize active recovery or rest. If 'Underreaching', consider adding intensity to your workouts.",
                detailedInsight: nil
            ))
        }
    }
}
