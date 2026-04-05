//
//  DetailedWellnessCharts.swift
//  HealthAnalytics
//
//  Detailed timeline-style charts for wellness metrics
//  Used on Today tab - no toggles, auto-show if data exists
//

import SwiftUI
import Charts

// MARK: - Detailed RHR Chart

struct DetailedRHRChart: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    private var filteredData: [HealthDataPoint] {
        let startDate = period.startDate(from: Date())
        return data.filter { $0.date >= startDate }
    }
    
    private var averageValueRaw: Double {
        guard !filteredData.isEmpty else { return 0 }
        return filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
    }
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        return "Avg: \(Int(averageValueRaw)) bpm"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: .spacingSm) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.statusWarning)
                Text("Resting Heart Rate")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(averageValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Chart {
                ForEach(filteredData, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("BPM", point.value)
                    )
                    .foregroundStyle(Color.statusWarning.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("BPM", point.value)
                    )
                    .foregroundStyle(Color.statusWarning.opacity(0.1).gradient)
                }
                
                if !filteredData.isEmpty {
                    RuleMark(y: .value("Average", averageValueRaw))
                        .foregroundStyle(Color.statusWarning.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text("\(Int(doubleValue))")
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Detailed HRV Chart

struct DetailedHRVChart: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    private var filteredData: [HealthDataPoint] {
        let startDate = period.startDate(from: Date())
        return data.filter { $0.date >= startDate }
    }
    
    private var averageValueRaw: Double {
        guard !filteredData.isEmpty else { return 0 }
        return filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
    }
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        return "Avg: \(Int(averageValueRaw)) ms"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: .spacingSm) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Color.statusOptimal)
                Text("Heart Rate Variability")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(averageValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Chart {
                ForEach(filteredData, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("HRV", point.value)
                    )
                    .foregroundStyle(Color.statusOptimal.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("HRV", point.value)
                    )
                    .foregroundStyle(Color.statusOptimal.opacity(0.1).gradient)
                }
                
                if !filteredData.isEmpty {
                    RuleMark(y: .value("Average", averageValueRaw))
                        .foregroundStyle(Color.statusOptimal.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text("\(Int(doubleValue))")
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Detailed Sleep Chart

struct DetailedSleepChart: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    private var filteredData: [HealthDataPoint] {
        let startDate = period.startDate(from: Date())
        return data.filter { $0.date >= startDate }
    }
    
    private var averageValueRaw: Double {
        guard !filteredData.isEmpty else { return 0 }
        return filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
    }
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        return String(format: "Avg: %.1f hrs", averageValueRaw)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: .spacingSm) {
                Image(systemName: "bed.double.fill")
                    .foregroundStyle(Color.accent)
                Text("Sleep")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(averageValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Chart {
                ForEach(filteredData, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(Color.accent.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(Color.accent.opacity(0.1).gradient)
                }
                
                if !filteredData.isEmpty {
                    RuleMark(y: .value("Average", averageValueRaw))
                        .foregroundStyle(Color.accent.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.1f", doubleValue))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Detailed Steps Chart

struct DetailedStepsChart: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    private var filteredData: [HealthDataPoint] {
        let startDate = period.startDate(from: Date())
        return data.filter { $0.date >= startDate }
    }
    
    private var averageValueRaw: Double {
        guard !filteredData.isEmpty else { return 0 }
        return filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
    }
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        return "Avg: \(Int(averageValueRaw)) steps"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: .spacingSm) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(Color.statusWarning)
                Text("Steps")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(averageValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Chart {
                ForEach(filteredData, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Steps", point.value)
                    )
                    .foregroundStyle(Color.statusWarning.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Steps", point.value)
                    )
                    .foregroundStyle(Color.statusWarning.opacity(0.1).gradient)
                }
                
                if !filteredData.isEmpty {
                    RuleMark(y: .value("Average", averageValueRaw))
                        .foregroundStyle(Color.statusWarning.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text("\(Int(doubleValue / 1000))k")
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Detailed Weight Chart

struct DetailedWeightChart: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    private var filteredData: [HealthDataPoint] {
        let startDate = period.startDate(from: Date())
        return data.filter { $0.date >= startDate }
    }
    
    private var averageValueRaw: Double {
        guard !filteredData.isEmpty else { return 0 }
        return filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
    }
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        return String(format: "Avg: %.1f lbs", averageValueRaw)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: .spacingSm) {
                Image(systemName: "scalemass.fill")
                    .foregroundStyle(Color.statusRest)
                Text("Weight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(averageValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Chart {
                ForEach(filteredData, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(Color.statusRest.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(Color.statusRest.opacity(0.1).gradient)
                }
                
                if !filteredData.isEmpty {
                    RuleMark(y: .value("Average", averageValueRaw))
                        .foregroundStyle(Color.statusRest.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.1f", doubleValue))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
