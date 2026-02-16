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
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        let avg = filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
        return "Avg: \(Int(avg)) bpm"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
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
                    .foregroundStyle(Color.red.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("BPM", point.value)
                    )
                    .foregroundStyle(Color.red.opacity(0.1).gradient)
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
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        let avg = filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
        return "Avg: \(Int(avg)) ms"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.green)
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
                    .foregroundStyle(Color.green.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("HRV", point.value)
                    )
                    .foregroundStyle(Color.green.opacity(0.1).gradient)
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
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        let avg = filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
        return String(format: "Avg: %.1f hrs", avg)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .foregroundStyle(.purple)
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
                    .foregroundStyle(Color.purple.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(Color.purple.opacity(0.1).gradient)
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
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        let avg = filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
        return "Avg: \(Int(avg / 1000))k steps"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.orange)
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
                    .foregroundStyle(Color.orange.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Steps", point.value)
                    )
                    .foregroundStyle(Color.orange.opacity(0.1).gradient)
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
    
    private var averageValue: String {
        guard !filteredData.isEmpty else { return "No data" }
        let avg = filteredData.map { $0.value }.reduce(0, +) / Double(filteredData.count)
        return String(format: "Avg: %.1f lbs", avg)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "scalemass.fill")
                    .foregroundStyle(.blue)
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
                    .foregroundStyle(Color.blue.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(Color.blue.opacity(0.1).gradient)
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
