//
//  HRVCard.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/31/26.
//


//
//  HRVCard.swift
//  HealthAnalytics
//
//  Replaces the existing HRVCard. Aggregates raw HRV samples down to
//  one value per day (morning-window strategy) before charting, so the
//  graph is a clean daily line instead of a spike forest.
//

import SwiftUI
import Charts
import HealthKit

struct HRVCard: View {
    let data: [HealthDataPoint]
    let period: TimePeriod
    
    /// One reading per day: best sample from the 5-10 AM window,
    /// or the earliest sample of the day as fallback.
    private var dailyData: [HealthDataPoint] {
        let cal = Calendar.current
        var buckets: [Date: [HealthDataPoint]] = [:]
        
        for point in data {
            let day = cal.startOfDay(for: point.date)
            buckets[day, default: []].append(point)
        }
        
        return buckets.map { (day, points) -> HealthDataPoint in
            let windowStart = cal.date(byAdding: .hour, value: 5,  to: day)!
            let windowEnd   = cal.date(byAdding: .hour, value: 10, to: day)!
            
            let morningPoints = points.filter {
                $0.date >= windowStart && $0.date < windowEnd
            }
            
            // Best reading in the morning window (highest = deepest sleep)
            if let best = morningPoints.max(by: { $0.value < $1.value }) {
                return HealthDataPoint(date: day, value: best.value)
            }
            // Fallback: earliest sample of the day
            return HealthDataPoint(date: day, value: points.min(by: { $0.date < $1.date })!.value)
        }.sorted { $0.date < $1.date }
    }
    
    private var currentValue: Int {
        guard let last = dailyData.last else { return 0 }
        return Int(last.value)
    }
    
    private var averageValue: Int {
        guard !dailyData.isEmpty else { return 0 }
        return Int(dailyData.map { $0.value }.reduce(0, +) / Double(dailyData.count))
    }
    
    /// 7-day trend: positive = improving, negative = declining
    private var trend: Double {
        guard dailyData.count >= 14 else { return 0 }
        let recent = dailyData.suffix(7).map  { $0.value }
        let prior  = Array(dailyData.suffix(14).prefix(7)).map { $0.value }
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let priorAvg  = prior.reduce(0, +) / Double(prior.count)
        return recentAvg - priorAvg
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HRV")
                        .font(.headline)
                    Text(period.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Current value
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(currentValue)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Chart — one point per day
            if !dailyData.isEmpty {
                Chart {
                    ForEach(dailyData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("HRV", point.value)
                        )
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                        
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("HRV", point.value)
                        )
                        .foregroundStyle(.green.opacity(0.08))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))").font(.caption2)
                            }
                        }
                        AxisGridLine().foregroundStyle(.gray.opacity(0.12))
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
                .frame(height: 100)
            }
            
            // Footer: avg + trend
            HStack {
                Text("Avg: \(averageValue) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if trend > 2 {
                    Text("↑ improving")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if trend < -2 {
                    Text("↓ declining")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if dailyData.count >= 14 {
                    Text("→ stable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
