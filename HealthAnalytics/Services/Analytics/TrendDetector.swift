//
//  TrendDetector.swift
//  HealthAnalytics
//
//  Created by Craig Faist.
//

import Foundation
import HealthKit
import SwiftUI

// MARK: - Data Models
// Defined here to be accessible globally

struct MetricTrend: Identifiable {
    let id = UUID()
    let metricName: String
    let currentValue: Double
    let baselineValue: Double?
    let trendDirection: TrendDirection
    let percentageChange: Double
    let status: TrendStatus
    let context: String
}

enum TrendDirection: String, Codable {
    case increasing
    case decreasing
    case stable
    
    var emoji: String {
        switch self {
        case .increasing: return "📈"
        case .decreasing: return "📉"
        case .stable: return "➡️"
        }
    }
}

enum TrendStatus: String, Codable {
    case improving
    case declining
    case neutral
    case warning
    
    var color: Color {
        switch self {
        case .improving: return .green
        case .declining: return .orange
        case .neutral: return .blue
        case .warning: return .red
        }
    }
}

// MARK: - Logic Engine

class TrendDetector {
    
    // Main function to detect trends across multiple metrics
    func detectTrends(restingHRData: [HealthDataPoint],
                      hrvData: [HealthDataPoint],
                      sleepData: [HealthDataPoint],
                      stepData: [HealthDataPoint],
                      weightData: [HealthDataPoint],
                      workouts: [WorkoutData]) -> [MetricTrend] {
        
        var trends: [MetricTrend] = []
        
        // 1. Analyze Resting Heart Rate (Lower is better)
        if let rhrTrend = analyzeMetric(data: restingHRData, name: "Resting Heart Rate", lowerIsBetter: true) {
            trends.append(rhrTrend)
        }
        
        // 2. Analyze HRV (Higher is better)
        if let hrvTrend = analyzeMetric(data: hrvData, name: "HRV", lowerIsBetter: false) {
            trends.append(hrvTrend)
        }
        
        // 3. Analyze Sleep (Higher is better)
        if let sleepTrend = analyzeMetric(data: sleepData, name: "Sleep Duration", lowerIsBetter: false) {
            trends.append(sleepTrend)
        }
        
        // 4. Analyze Steps (Higher is better) - RESTORED
        if let stepTrend = analyzeMetric(data: stepData, name: "Daily Steps", lowerIsBetter: false) {
            trends.append(stepTrend)
        }

        // 5. Analyze Weight (Lower is usually targeted, but context dependent. Assume lower for now) - RESTORED
        if let weightTrend = analyzeMetric(data: weightData, name: "Body Weight", lowerIsBetter: true) {
            trends.append(weightTrend)
        }
        
        // 6. Analyze Training Frequency (FIXED: Filter for last 30 days)
        let now = Date()
        if let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            
            // Only count workouts that actually happened in the analysis window
            let recentWorkouts = workouts.filter { $0.startDate >= thirtyDaysAgo }
            
            // Formula: (Workouts / 30 days) * 7 = Weekly Avg
            let frequency = Double(recentWorkouts.count) / 30.0 * 7.0
            
            trends.append(MetricTrend(
                metricName: "Training Frequency",
                currentValue: frequency,
                baselineValue: nil,
                trendDirection: .stable,
                percentageChange: 0.0,
                status: .neutral,
                context: String(format: "%.1f workouts/week (last 30 days)", frequency)
            ))
        }
        
        return trends
    }
    
    // Generic Helper to analyze simple High/Low trends
    // This replaces the multiple copy-pasted functions from the old version
    private func analyzeMetric(data: [HealthDataPoint], name: String, lowerIsBetter: Bool) -> MetricTrend? {
        // Require at least 14 days of data to form a trend
        guard data.count >= 14 else { return nil }
        
        let sortedData = data.sorted { $0.date < $1.date }
        
        // Split into "Current Week" vs "Previous 3 Weeks" (Baseline)
        let splitIndex = max(0, sortedData.count - 7)
        let recentData = Array(sortedData[splitIndex...])
        let baselineData = Array(sortedData[0..<splitIndex])
        
        guard !recentData.isEmpty, !baselineData.isEmpty else { return nil }
        
        let recentAvg = recentData.map { $0.value }.reduce(0, +) / Double(recentData.count)
        let baselineAvg = baselineData.map { $0.value }.reduce(0, +) / Double(baselineData.count)
        
        let diff = recentAvg - baselineAvg
        let percentChange = baselineAvg != 0 ? (diff / baselineAvg) * 100 : 0
        
        // Determine Direction
        let direction: TrendDirection
        if abs(percentChange) < 1.0 {
            direction = .stable
        } else {
            direction = diff > 0 ? .increasing : .decreasing
        }
        
        // Determine Status (Good/Bad)
        let status: TrendStatus
        if direction == .stable {
            status = .neutral
        } else if lowerIsBetter {
            // Lower is better (e.g. RHR, Weight)
            status = diff < 0 ? .improving : .declining
        } else {
            // Higher is better (e.g. HRV, Sleep, Steps)
            status = diff > 0 ? .improving : .declining
        }
        
        return MetricTrend(
            metricName: name,
            currentValue: recentAvg,
            baselineValue: baselineAvg,
            trendDirection: direction,
            percentageChange: percentChange,
            status: status,
            context: "\(Int(abs(percentChange)))% vs baseline"
        )
    }
}
