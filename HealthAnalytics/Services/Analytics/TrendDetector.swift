//
//  TrendDetector.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import Foundation

struct TrendDetector {
    
    // MARK: - Trend Models
    
    struct MetricTrend {
        let metric: String
        let direction: TrendDirection
        let percentChange: Double
        let period: String
        let message: String
        
        enum TrendDirection {
            case improving
            case declining
            case stable
            
            var emoji: String {
                switch self {
                case .improving: return "📈"
                case .declining: return "📉"
                case .stable: return "➡️"
                }
            }
            
            var color: String {
                switch self {
                case .improving: return "green"
                case .declining: return "orange"
                case .stable: return "blue"
                }
            }
        }

        enum TrendPeriod: String {
            case acute = "7 days"
            case shortTerm = "14 days"
            case longTerm = "90 days"
        }
    }
    
    // MARK: - Detect Trends
    
    /// Analyzes trends in key health metrics
    func detectTrends(
        restingHRData: [HealthDataPoint],
        hrvData: [HealthDataPoint],
        sleepData: [HealthDataPoint],
        stepData: [HealthDataPoint],
        weightData: [HealthDataPoint]
    ) -> [MetricTrend] {
        
        var trends: [MetricTrend] = []
        
        // Resting HR trend (lower is better)
        if let rhrTrend = analyzeTrend(
            data: restingHRData,
            metricName: "Resting Heart Rate",
            lowerIsBetter: true,
            unit: "bpm"
        ) {
            trends.append(rhrTrend)
        }
        
        // HRV trend (higher is better)
        // REFINED HRV: Analyze over 14 days rather than 90 for better sensitivity
        if let hrvTrend = analyzeTrend(
            data: hrvData,
            metricName: "HRV",
            lowerIsBetter: false,
            unit: "ms",
            maxDays: 14 // Cap HRV to 2 weeks for "Recovery" context
        ) {
            trends.append(hrvTrend)
        }
        
        // Sleep trend (higher is better, target ~7-9 hours)
        if let sleepTrend = analyzeTrend(
            data: sleepData,
            metricName: "Sleep Duration",
            lowerIsBetter: false,
            unit: "hours",
            optimalRange: 7.0...9.0
        ) {
            trends.append(sleepTrend)
        }
        
        // Step trend (higher is better)
        if let stepTrend = analyzeTrend(
            data: stepData,
            metricName: "Daily Steps",
            lowerIsBetter: false,
            unit: "steps"
        ) {
            trends.append(stepTrend)
        }
        
        // NEW: Body Weight Trend
        if let weightTrend = analyzeTrend(
            data: weightData,
            metricName: "Body Weight",
            lowerIsBetter: true, // Assuming weight loss/maintenance for biking app
            unit: "lbs"
        ) {
            trends.append(weightTrend)
        }
        
        return trends
    }
    
    // MARK: - Helper Methods
    
    private func analyzeTrend(
        data: [HealthDataPoint],
        metricName: String,
        lowerIsBetter: Bool,
        unit: String,
        optimalRange: ClosedRange<Double>? = nil,
        maxDays: Int = 90 // Default to 90, but override for HRV
    ) -> MetricTrend? {
        
        guard data.count >= 7 else { return nil }
        
        // Cap analysis to the requested window
        let dataToAnalyze = data.count > maxDays ? Array(data.suffix(maxDays)) : data
        
        // Split into two periods: recent vs. earlier
        let midpoint = dataToAnalyze.count / 2
        let earlierPeriod = Array(dataToAnalyze.prefix(midpoint))
        let recentPeriod = Array(dataToAnalyze.suffix(dataToAnalyze.count - midpoint))
        
        guard !earlierPeriod.isEmpty, !recentPeriod.isEmpty else { return nil }
        
        let earlierAvg = earlierPeriod.map { $0.value }.reduce(0, +) / Double(earlierPeriod.count)
        let recentAvg = recentPeriod.map { $0.value }.reduce(0, +) / Double(recentPeriod.count)
        
        let absoluteChange = recentAvg - earlierAvg
        let percentChange = (absoluteChange / earlierAvg) * 100
        
        // Determine direction based on whether lower is better
        let direction: MetricTrend.TrendDirection
        let isImproving: Bool
        
        if lowerIsBetter {
            isImproving = absoluteChange < 0
        } else {
            isImproving = absoluteChange > 0
        }
        
        // Check if change is significant (>5%)
        if abs(percentChange) < 5.0 {
            direction = .stable
        } else {
            direction = isImproving ? .improving : .declining
        }
        
        // Generate message
        let message = generateTrendMessage(
            metricName: metricName,
            direction: direction,
            percentChange: abs(percentChange),
            recentAvg: recentAvg,
            unit: unit,
            optimalRange: optimalRange
        )
        
        let daysAnalyzed = dataToAnalyze.count
        let period = "\(daysAnalyzed) days"
        
        print("📊 \(metricName) Trend:")
        print("   Earlier avg: \(String(format: "%.1f", earlierAvg))")
        print("   Recent avg: \(String(format: "%.1f", recentAvg))")
        print("   Change: \(String(format: "%.1f", percentChange))%")
        print("   Direction: \(direction)")
        
        return MetricTrend(
            metric: metricName,
            direction: direction,
            percentChange: percentChange,
            period: period,
            message: message
        )
    }
    
    private func generateTrendMessage(
        metricName: String,
        direction: MetricTrend.TrendDirection,
        percentChange: Double,
        recentAvg: Double,
        unit: String,
        optimalRange: ClosedRange<Double>?
    ) -> String {
        
        let formattedValue: String
        if metricName == "Daily Steps" {
            formattedValue = "\(Int(recentAvg).formatted())"
        } else {
            formattedValue = String(format: "%.1f", recentAvg)
        }
        
        switch direction {
        case .improving:
            var message = "\(metricName) is improving by \(String(format: "%.1f", percentChange))%"
            message += " (now \(formattedValue) \(unit))"
            
            if let range = optimalRange, range.contains(recentAvg) {
                message += " - in optimal range!"
            }
            
            return message
            
        case .declining:
            var message = "\(metricName) has declined by \(String(format: "%.1f", percentChange))%"
            message += " (now \(formattedValue) \(unit))"
            
            if let range = optimalRange, !range.contains(recentAvg) {
                message += " - below optimal range"
            }
            
            return message
            
        case .stable:
            var message = "\(metricName) is stable at \(formattedValue) \(unit)"
            
            if let range = optimalRange {
                if range.contains(recentAvg) {
                    message += " - maintaining optimal range"
                } else {
                    message += " - consider adjusting to reach optimal range"
                }
            }
            
            return message
        }
    }
}
