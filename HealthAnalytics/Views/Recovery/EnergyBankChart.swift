//
//  EnergyBankChart.swift
//  HealthAnalytics
//

import SwiftUI
import Charts

struct EnergyBankDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let energy: Double
    let isProjected: Bool
}

struct EnergyBankChart: View {
    let intraDay: RecoveryDecayService.IntraDayReadiness?
    let baselineScore: Int?
    let todayWorkouts: [WorkoutData]
    
    @Environment(\.colorScheme) var colorScheme
    
    var chartData: [EnergyBankDataPoint] {
        guard let intra = intraDay, let baseline = baselineScore else {
            return []
        }
        
        var points: [EnergyBankDataPoint] = []
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let decayService = RecoveryDecayService()
        
        // Sample every 30 minutes from startOfDay to endOfDay
        var currentTime = startOfDay
        while currentTime <= endOfDay {
            // For projected points, we only want to decay workouts that have ALREADY occurred.
            // calculateIntraDayReadiness filters: $0.startDate >= today && $0.endDate <= now.
            // If we pass currentTime as 'now', it will correctly include workouts that happened before currentTime.
            // If currentTime is in the future, it shouldn't include future workouts (unless logged, which is impossible).
            
            let simulatedIntra = decayService.calculateIntraDayReadiness(
                baselineScore: baseline,
                todayWorkouts: todayWorkouts,
                now: currentTime
            )
            
            points.append(EnergyBankDataPoint(
                time: currentTime,
                energy: Double(simulatedIntra.currentScore),
                isProjected: currentTime > now
            ))
            
            currentTime = calendar.date(byAdding: .minute, value: 30, to: currentTime)!
        }
        
        // Also ensure 'now' is explicitly plotted to get a crisp transition to dotted line
        let currentIntra = decayService.calculateIntraDayReadiness(
            baselineScore: baseline,
            todayWorkouts: todayWorkouts,
            now: now
        )
        points.append(EnergyBankDataPoint(
            time: now,
            energy: Double(currentIntra.currentScore),
            isProjected: false
        ))
        
        return points.sorted(by: { $0.time < $1.time })
    }

    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
            Text("Energy Bank")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if chartData.isEmpty {
                Text("Not enough data to calculate energy bank.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Energy", point.energy)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(point.isProjected ? AppColors.recovery.opacity(0.5) : AppColors.recovery)
                        .lineStyle(StrokeStyle(lineWidth: 3, dash: point.isProjected ? [5, 5] : []))
                        
                        AreaMark(
                            x: .value("Time", point.time),
                            yStart: .value("Min", 0),
                            yEnd: .value("Energy", point.energy)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(
                            colors: [
                                AppColors.recovery.opacity(point.isProjected ? 0.2 : 0.4),
                                AppColors.recovery.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.hour())
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXScale(domain: Calendar.current.startOfDay(for: Date())...Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 200)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Current Energy")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let intra = intraDay {
                            Text("\(intra.currentScore)%")
                                .font(.title2.bold())
                                .foregroundStyle(AppColors.recovery)
                        } else {
                            Text("--")
                                .font(.title2.bold())
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Full Recovery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let intra = intraDay {
                            Text(intra.recoveryPoint, format: .dateTime.hour().minute())
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                        } else {
                            Text("--")
                                .font(.subheadline.bold())
                        }
                    }
                }
                .padding(.top, .spacingSm)
            }
            } // Close VStack
        } // Close Button
        .buttonStyle(.plain)
        .padding()
        .solidCard()
        .sheet(isPresented: $showDetail) {
            MetricConditionDetailView(config: MetricDisplayConfig(
                id: "energy_bank",
                title: "Intra-Day Energy Bank",
                icon: "battery.100",
                currentValueFormatted: intraDay != nil ? "\(intraDay!.currentScore)%" : "--",
                status: (intraDay?.currentScore ?? 0) > 40 ? .good : .needsAttention,
                citation: nil,
                thresholdBarValue: nil,
                conditionReasoning: "Your energy bank reflects your dynamic readiness score throughout the day, decaying after workouts and recovering over time.",
                guidanceText: "Monitor this chart to time your workouts optimally. Train when energy is high, and prioritize rest when it dips.",
                detailedInsight: nil
            ))
        }
    }
}
