//
//  UnifiedTrainingLoadCard.swift
//  HealthAnalytics
//
//  Consolidated training load display combining ACWR, trend, and breakdown
//

import SwiftUI
import Charts

struct UnifiedTrainingLoadCard: View {
    let assessment: PredictiveReadinessService.ReadinessAssessment
    let trend: [ACWRDataPoint]
    let summary: TrainingLoadCalculator.TrainingLoadSummary?
    let primaryActivity: String
    let extendedData: TrainingLoadVisualizationService.LoadVisualizationData?
    
    @State private var showInfoSheet = false
    @State private var showExtendedView = false
    @State private var selectedDate: Date?
    
    private var hasValidTrend: Bool {
        let values = trend.map { $0.value }
        guard let min = values.min(), let max = values.max() else { return false }
        return (max - min) > 0.05
    }
    
    private var statusColor: Color {
        switch assessment.trend {
        case .building: return .orange
        case .optimal: return .green
        case .detraining: return .blue
        }
    }
    
    private var statusLabel: String {
        switch assessment.trend {
        case .building: return "Building"
        case .optimal: return "Optimal"
        case .detraining: return "Detraining"
        }
    }
    
    private var statusEmoji: String {
        switch assessment.trend {
        case .building: return "⚠️"
        case .optimal: return "✅"
        case .detraining: return "📉"
        }
    }
    
    private var interpretation: String {
        let acwr = assessment.acwr
        if acwr < 0.8 {
            return "Training load is lower than your 28-day average (detraining). Check your recovery metrics before increasing volume."
        } else if acwr <= 1.3 {
            return "Training load is in the optimal zone. Your acute load matches your chronic fitness level."
        } else if acwr <= 1.5 {
            return "Training load is elevated. This is manageable short-term but watch for signs of fatigue."
        } else {
            return "Training load is very high relative to your fitness. High injury risk - prioritize recovery."
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Compact header
            HStack {
                HStack(spacing: .spacingXs) {
                    Text("TRAINING LOAD")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Color.accent)
                    }
                }

                Spacer()

                // Compact status + ACWR
                HStack(spacing: .spacingSm) {
                    Text(statusEmoji)
                        .font(.title3)
                    
                    Text(statusLabel)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                    
                    Text(String(format: "%.2f", assessment.acwr))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                }
            }
            
            // TSS Metrics (what athletes understand)
            if let summary = summary {
                if summary.weeklyTSS == 0 && summary.ctl == 0 {
                    HStack(spacing: .spacingSm) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusWarning)

                        Text("No training data in the last 28 days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, .spacingSm)
                    .padding(.horizontal, 10)
                    .background(Color.statusWarning.opacity(0.1))
                    .cornerRadius(.radiusSm)
                } else {
                    VStack(spacing: .spacingSm) {
                        // Yesterday TSS
                        HStack {
                            Text("Yesterday:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(summary.yesterdayTSS == 0 ? "Rest day" : "\(Int(summary.yesterdayTSS)) TSS")
                                .font(.callout)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        // 7-day, 6-week average, 6-week daily average
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("7-day")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(summary.weeklyTSS)) TSS")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("6-Wk Avg")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(summary.sixWeekTSS / 6)) TSS")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("6-Wk Daily Avg")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(summary.sixWeekTSS / 42))")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
            } else {
                // Fallback to old display if summary not available
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Acute (7d)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(assessment.acuteLoad == 0 ? "—" : String(format: "%.1f", assessment.acuteLoad))
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(assessment.acuteLoad == 0 ? .secondary : .primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chronic (28d)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f", assessment.chronicLoad))
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                }
            }
            
            // Compact 7-Day Trend Chart
            if hasValidTrend {
                // Selected value display (always shown with fixed height to prevent bouncing)
                Group {
                    if let date = selectedDate,
                       let selectedPoint = trend.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                        HStack(spacing: .spacingSm) {
                            Text(selectedPoint.date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", selectedPoint.value))
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(statusColor)
                        }
                    } else {
                        Text(" ")  // Placeholder to maintain height when no data point selected
                            .font(.callout)
                            .foregroundStyle(.clear)
                    }
                }
                .frame(height: 20)  // Fixed height always maintained
                .frame(maxWidth: .infinity, alignment: .center)
                
                Chart {
                    // Sweet spot zone (0.8 - 1.3)
                    RectangleMark(
                        xStart: .value("Start", trend.first?.date ?? Date()),
                        xEnd: .value("End", trend.last?.date ?? Date()),
                        yStart: .value("Low", 0.8),
                        yEnd: .value("High", 1.3)
                    )
                    .foregroundStyle(.green.opacity(0.15))
                    .annotation(position: .overlay, alignment: .topTrailing) {
                        Text("Sweet Spot")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.6))
                            .padding(.trailing, 4)
                            .padding(.top, 4)
                    }
                    
                    // Baseline at 1.0
                    RuleMark(y: .value("Baseline", 1.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.gray.opacity(0.5))
                    
                    // Actual trend line
                    ForEach(trend) { day in
                        LineMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Ratio", day.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(statusColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Ratio", day.value)
                        )
                        .foregroundStyle(statusColor)
                    }
                    
                    // Selection indicator (always show when scrubbing)
                    if let date = selectedDate {
                        RuleMark(x: .value("Selected", date, unit: .day))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 80)
                .chartYScale(domain: 0...2.0)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.1f", v))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
            }
            
            // Compact interpretation + recommendation
            VStack(alignment: .leading, spacing: .spacingSm) {
                Text(interpretation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let summary = summary {
                    HStack(spacing: .spacingSm) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusMonitoring)

                        Text(summary.recommendation)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, .spacingSm)
                    .padding(.horizontal, 10)
                    .background(Color.statusMonitoring.opacity(0.1))
                    .cornerRadius(.radiusSm)
                }
            }
            
            // Compact Extended Analysis Button
            if let extendedData = extendedData {
                Button {
                    showExtendedView = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Extended Analysis")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text("90-day trends, patterns & danger zones")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.vertical, .spacingSm)
                }
                .sheet(isPresented: $showExtendedView) {
                    NavigationStack {
                        TrainingLoadVisualizationView(data: extendedData)
                    }
                }
            }
        }
        .padding(.spacingMd)
        .sheet(isPresented: $showInfoSheet) {
            ACWRExplainerSheet()
        }
    }
}

#Preview {
    UnifiedTrainingLoadCard(
        assessment: PredictiveReadinessService.ReadinessAssessment(
            acwr: 0.95,
            chronicLoad: 100,
            acuteLoad: 95,
            trend: .optimal
        ),
        trend: [
            ACWRDataPoint(date: Date().addingTimeInterval(-6*86400), value: 1.1),
            ACWRDataPoint(date: Date().addingTimeInterval(-5*86400), value: 1.15),
            ACWRDataPoint(date: Date().addingTimeInterval(-4*86400), value: 1.2),
            ACWRDataPoint(date: Date().addingTimeInterval(-3*86400), value: 1.25),
            ACWRDataPoint(date: Date().addingTimeInterval(-2*86400), value: 1.1),
            ACWRDataPoint(date: Date().addingTimeInterval(-1*86400), value: 1.0),
            ACWRDataPoint(date: Date(), value: 0.95)
        ],
        summary: TrainingLoadCalculator.TrainingLoadSummary(
            acuteLoad: 95,
            chronicLoad: 100,
            acuteChronicRatio: 0.95,
            status: .optimal,
            recommendation: "Well balanced. Safe to maintain or gradually increase.",
            ewmaAcuteLoad: 95,
            ewmaChronicLoad: 100,
            ewmaRatio: 0.95,
            monotony: 1.2,
            strain: 114,
            weeklyLoadChange: 5.0,
            yesterdayTSS: 85,
            weeklyTSS: 450,
            atl: 450,
            ctl: 2800,
            sixWeekTSS: 2700
        ),
        primaryActivity: "Ride",
        extendedData: nil
    )
    .cardStyle(for: .workouts)
    .padding()
}
