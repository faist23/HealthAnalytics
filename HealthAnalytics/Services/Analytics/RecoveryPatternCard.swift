//
//  RecoveryPatternCard.swift
//  HealthAnalytics
//

import SwiftUI
import Charts
import HealthKit

// MARK: - Recovery Analysis

/// Looks at every workout in the data, finds HRV on the days after,
/// and groups them into buckets: workout day, +1 day, +2 days, +3 days.
/// Returns the average HRV for each bucket.
enum RecoveryAnalyzer {
    
    struct RecoveryPattern {
        let buckets: [Bucket]           // ordered: workout day → +3
        let workoutCount: Int           // how many workouts contributed
        let averageHRV: Double          // overall baseline for context
        
        struct Bucket {
            let label: String           // "Workout", "+1 day", "+2 days", "+3 days"
            let averageHRV: Double
            let sampleCount: Int
        }
        
        /// True when we have enough data AND the bars actually show a curve.
        /// If all buckets are within 5% of each other, there's no pattern —
        /// just flat noise. Don't show the chart for that.
        var hasPattern: Bool {
            guard workoutCount >= 3 else { return false }
            let populated = buckets.filter { $0.sampleCount > 0 }.map { $0.averageHRV }
            guard populated.count >= 2 else { return false }
            let lo = populated.min()!
            let hi = populated.max()!
            guard lo > 0 else { return false }
            let spread = (hi - lo) / lo   // relative spread
            return spread >= 0.05         // at least 5% difference between any two buckets
        }
    }
    
    static func analyze(
        hrvData: [HealthDataPoint],
        workouts: [WorkoutData]
    ) -> RecoveryPattern? {
        let cal = Calendar.current
        
        // Step 1: collapse HRV to one value per day (morning window strategy)
        let dailyHRV = morningAggregate(hrvData, cal: cal)
        guard !dailyHRV.isEmpty else { return nil }
        
        // Build a lookup: day → HRV value
        var hrvByDay: [Date: Double] = [:]
        for point in dailyHRV {
            hrvByDay[cal.startOfDay(for: point.date)] = point.value
        }
        
        // Step 2: for each workout, grab HRV on that day and the 3 days after
        var buckets: [[Double]] = [[], [], [], []]   // index 0 = workout day, 1 = +1, etc.
        var contributingWorkouts = 0
        
        // Group workouts by day first (multiple workouts in one day = one event)
        var workoutDays = Set<Date>()
        for w in workouts {
            workoutDays.insert(cal.startOfDay(for: w.startDate))
        }
        
        for day in workoutDays {
            var anyHRVFound = false
            for offset in 0..<4 {
                guard let targetDay = cal.date(byAdding: .day, value: offset, to: day) else { continue }
                if let hrv = hrvByDay[targetDay] {
                    buckets[offset].append(hrv)
                    anyHRVFound = true
                }
            }
            if anyHRVFound { contributingWorkouts += 1 }
        }
        
        // Step 3: compute averages
        let overallAvg = dailyHRV.map { $0.value }.reduce(0, +) / Double(dailyHRV.count)
        
        let labels = ["Workout day", "+1 day", "+2 days", "+3 days"]
        let result = zip(labels, buckets).map { (label, values) -> RecoveryPattern.Bucket in
            let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            return RecoveryPattern.Bucket(label: label, averageHRV: avg, sampleCount: values.count)
        }
        
        return RecoveryPattern(
            buckets: result,
            workoutCount: contributingWorkouts,
            averageHRV: overallAvg
        )
    }
    
    /// Morning-window HRV aggregation: one value per day.
    /// 5-10 AM window, take highest (deepest sleep reading). Fallback: earliest sample.
    private static func morningAggregate(_ data: [HealthDataPoint], cal: Calendar) -> [HealthDataPoint] {
        var buckets: [Date: [HealthDataPoint]] = [:]
        for p in data {
            buckets[cal.startOfDay(for: p.date), default: []].append(p)
        }
        return buckets.map { (day, points) -> HealthDataPoint in
            let start = cal.date(byAdding: .hour, value: 5,  to: day)!
            let end   = cal.date(byAdding: .hour, value: 10, to: day)!
            let morning = points.filter { $0.date >= start && $0.date < end }
            if let best = morning.max(by: { $0.value < $1.value }) {
                return HealthDataPoint(date: day, value: best.value)
            }
            return HealthDataPoint(date: day, value: points.min(by: { $0.date < $1.date })!.value)
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - Chart Data Model

/// Flat row for the SwiftUI Chart — one row per bar
private struct BarDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let isBelowBaseline: Bool   // drives color: red if below overall avg
}

// MARK: - View

struct RecoveryPatternCard: View {
    let hrvData:   [HealthDataPoint]
    let rhrData:   [HealthDataPoint]
    let sleepData: [HealthDataPoint]
    let workouts:  [WorkoutData]
    
    private var pattern: RecoveryAnalyzer.RecoveryPattern? {
        RecoveryAnalyzer.analyze(hrvData: hrvData, workouts: workouts)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pattern = pattern, pattern.hasPattern {
                // There's an actual recovery curve — show the chart
                PatternView(pattern: pattern)
            } else {
                // Flat or not enough data — plain text summary instead
                WeeklySnapshotView(
                    hrvData:   hrvData,
                    rhrData:   rhrData,
                    sleepData: sleepData,
                    workouts:  workouts
                )
            }
        }
        .padding()
    }
}

// MARK: - Pattern View (has enough data)

private struct PatternView: View {
    let pattern: RecoveryAnalyzer.RecoveryPattern
    
    private var chartData: [BarDataPoint] {
        pattern.buckets
            .filter { $0.sampleCount > 0 }
            .map { bucket in
                BarDataPoint(
                    label: bucket.label,
                    value: bucket.averageHRV,
                    isBelowBaseline: bucket.averageHRV < pattern.averageHRV
                )
            }
    }
    
    /// Y-axis range: start at 0 (BarMark always draws from 0) and pad above the data
    private var yRange: ClosedRange<Double> {
        guard let hi = chartData.map({ $0.value }).max() else { return 0...100 }
        return 0...(hi * 1.25)   // 25% headroom above the tallest bar
    }
    
    var body: some View {
        // Header
        HStack {
            Text("Recovery Pattern")
                .font(.headline)
            Spacer()
            Text("\(pattern.workoutCount) workouts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
        
        // Subtitle — what this chart is actually showing
        Text("Average HRV in the days following a workout")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 12)
        
        // The chart
        Chart {
            // Baseline reference line — your overall HRV average
            RuleMark(y: .value("Baseline", pattern.averageHRV))
                .foregroundStyle(.gray.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            
            // The bars
            ForEach(chartData) { point in
                BarMark(
                    x: .value("Day", point.label),
                    y: .value("HRV", point.value)
                )
                .foregroundStyle(point.isBelowBaseline ? Color.red.opacity(0.6) : Color.green.opacity(0.6))
                .cornerRadius(4)
            }
        }
        .chartYScale(domain: yRange)
        .clipped()
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let v = value.as(Double.self) {
                    AxisValueLabel {
                        Text("\(Int(v)) ms").font(.caption2).foregroundStyle(.secondary)
                    }
                    AxisGridLine().foregroundStyle(.gray.opacity(0.08))
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                if let label = value.as(String.self) {
                    AxisValueLabel {
                        Text(label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 160)
        .padding(.bottom, 12)
        
        // Legend row: dashed line = baseline, colors = below/above
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Line()
                    .stroke(.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: 24, height: 1)
                Text("Your avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 12, height: 10)
                Text("Below avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green.opacity(0.6))
                    .frame(width: 12, height: 10)
                Text("Above avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Weekly Snapshot (fallback when no recovery pattern exists)

/// Plain text summary: compares last 7 days to the prior 7 for each metric.
/// Only surfaces a line when something is actually worth noting.
private struct WeeklySnapshotView: View {
    let hrvData:   [HealthDataPoint]
    let rhrData:   [HealthDataPoint]
    let sleepData: [HealthDataPoint]
    let workouts:  [WorkoutData]
    
    private var lines: [SnapshotLine] {
        var result: [SnapshotLine] = []
        let cal = Calendar.current
        let now = Date()
        let weekAgo     = cal.date(byAdding: .day, value: -7,  to: now)!
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now)!
        
        // HRV
        let hrvThisWeek = weekAvg(hrvData, from: weekAgo,     to: now,     cal: cal)
        let hrvLastWeek = weekAvg(hrvData, from: twoWeeksAgo, to: weekAgo, cal: cal)
        if let t = hrvThisWeek {
            if let l = hrvLastWeek {
                let pct = ((t - l) / l) * 100
                if pct > 5 {
                    result.append(SnapshotLine(icon: "waveform.path.ecg", text: "HRV up \(Int(pct))% to \(Int(t)) ms", color: .green))
                } else if pct < -5 {
                    result.append(SnapshotLine(icon: "waveform.path.ecg", text: "HRV down \(Int(abs(pct)))% to \(Int(t)) ms", color: .red))
                } else {
                    result.append(SnapshotLine(icon: "waveform.path.ecg", text: "HRV steady at \(Int(t)) ms", color: .secondary))
                }
            } else {
                result.append(SnapshotLine(icon: "waveform.path.ecg", text: "HRV averaging \(Int(t)) ms", color: .secondary))
            }
        }
        
        // Sleep
        let sleepThisWeek = weekAvg(sleepData, from: weekAgo,     to: now,     cal: cal)
        let sleepLastWeek = weekAvg(sleepData, from: twoWeeksAgo, to: weekAgo, cal: cal)
        if let t = sleepThisWeek {
            if t < 7.0 {
                if let l = sleepLastWeek, t < l - 0.3 {
                    result.append(SnapshotLine(icon: "bed.double.fill", text: "Sleep down to \(fmt1(t)) hrs (was \(fmt1(l)))", color: .red))
                } else {
                    result.append(SnapshotLine(icon: "bed.double.fill", text: "Sleep averaging \(fmt1(t)) hrs — below 7 hr target", color: .yellow))
                }
            } else if let l = sleepLastWeek, t > l + 0.3 {
                result.append(SnapshotLine(icon: "bed.double.fill", text: "Sleep up to \(fmt1(t)) hrs", color: .green))
            }
            // If sleep is ≥7 and stable, skip — nothing to note
        }
        
        // RHR
        let rhrThisWeek = weekAvg(rhrData, from: weekAgo,     to: now,     cal: cal)
        let rhrLastWeek = weekAvg(rhrData, from: twoWeeksAgo, to: weekAgo, cal: cal)
        if let t = rhrThisWeek, let l = rhrLastWeek {
            let diff = t - l
            if diff > 2 {
                result.append(SnapshotLine(icon: "heart.fill", text: "Resting HR up \(Int(diff)) bpm to \(Int(t))", color: .red))
            } else if diff < -2 {
                result.append(SnapshotLine(icon: "heart.fill", text: "Resting HR down \(Int(abs(diff))) bpm to \(Int(t))", color: .green))
            }
        }
        
        // Workout count
        let recentWorkouts = workouts.filter { $0.startDate >= weekAgo }
        if !recentWorkouts.isEmpty {
            result.append(SnapshotLine(icon: "figure.run", text: "\(recentWorkouts.count) workout\(recentWorkouts.count == 1 ? "" : "s") this week", color: .secondary))
        }
        
        // Cap at 3 lines — priority order is already correct (HRV, sleep, RHR, workouts)
        return Array(result.prefix(3))
    }
    
    var body: some View {
        // Header
        Text("This Week")
            .font(.headline)
            .padding(.bottom, 12)
        
        if lines.isEmpty {
            Text("Collecting data… check back after a few days of tracking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(lines.indices, id: \.self) { i in
                let line = lines[i]
                HStack(spacing: 10) {
                    Image(systemName: line.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(line.color)
                        .frame(width: 18)
                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                if i < lines.count - 1 {
                    Divider().padding(.vertical, 8)
                }
            }
        }
    }
    
    // MARK: - helpers
    
    private struct SnapshotLine {
        let icon: String
        let text: String
        let color: Color
    }
    
    /// Average of all data points within a date window, collapsed to daily first
    private func weekAvg(_ data: [HealthDataPoint], from: Date, to: Date, cal: Calendar) -> Double? {
        let inWindow = data.filter { $0.date >= from && $0.date < to }
        guard !inWindow.isEmpty else { return nil }
        // Daily collapse
        var buckets: [Date: [Double]] = [:]
        for p in inWindow {
            buckets[cal.startOfDay(for: p.date), default: []].append(p.value)
        }
        let dailyAvgs = buckets.values.map { $0.reduce(0, +) / Double($0.count) }
        return dailyAvgs.reduce(0, +) / Double(dailyAvgs.count)
    }
    
    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }
}

// MARK: - Helper: 1px dashed line shape for legend

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
