//
//  TemporalModelingService.swift
//  HealthAnalytics
//
//  Multi-model architecture: Recency, Seasonal, and Longitudinal analysis
//  Provides insights across different timescales
//

import Foundation
import CoreML
import CreateML
import HealthKit

struct TemporalModelingService {
    
    // MARK: - Temporal Analysis Result
    
    struct TemporalAnalysis {
        let recency: RecencyAnalysis
        let seasonal: SeasonalAnalysis
        let longitudinal: LongitudinalAnalysis
        let synthesis: TemporalSynthesis
        
        struct RecencyAnalysis {
            let currentForm: FormMetrics
            let trend: Trend
            let volatility: Double
            let timeWindow: String // "Last 30 days"
            
            struct FormMetrics {
                let averagePower: Double?
                let averageSpeed: Double?
                let trainingLoad: Double
                let consistency: Double // 0-1
            }
            
            enum Trend {
                case improving(percentChange: Double)
                case stable
                case declining(percentChange: Double)
                
                var description: String {
                    switch self {
                    case .improving(let pct): return "↑ Improving \(String(format: "+%.1f%%", pct))"
                    case .stable: return "→ Stable"
                    case .declining(let pct): return "↓ Declining \(String(format: "%.1f%%", pct))"
                    }
                }
                
                var emoji: String {
                    switch self {
                    case .improving: return "📈"
                    case .stable: return "➡️"
                    case .declining: return "📉"
                    }
                }
            }
        }
        
        struct SeasonalAnalysis {
            let currentSeasonPerformance: SeasonMetrics
            let bestSeason: Season
            let seasonalPattern: [Season: SeasonMetrics]
            let yearOverYearChange: Double? // % change vs same time last year
            
            struct SeasonMetrics {
                let season: Season
                let averagePerformance: Double
                let sampleSize: Int
                let confidence: StatisticalResult.ConfidenceLevel
            }
            
            enum Season: String, CaseIterable {
                case winter = "Winter"
                case spring = "Spring"
                case summer = "Summer"
                case fall = "Fall"
                
                static func from(date: Date) -> Season {
                    let month = Calendar.current.component(.month, from: date)
                    switch month {
                    case 12, 1, 2: return .winter
                    case 3, 4, 5: return .spring
                    case 6, 7, 8: return .summer
                    case 9, 10, 11: return .fall
                    default: return .summer
                    }
                }
                
                var emoji: String {
                    switch self {
                    case .winter: return "❄️"
                    case .spring: return "🌸"
                    case .summer: return "☀️"
                    case .fall: return "🍂"
                    }
                }
            }
        }
        
        struct LongitudinalAnalysis {
            let overallTrend: LongTermTrend
            let peakPeriods: [PeakPeriod]
            let growthRate: Double // % per year
            let timespan: String // "2015-2025"
            
            enum LongTermTrend {
                case strengthening(percentChange: Double)
                case plateaued
                case weakening(percentChange: Double)
                
                var description: String {
                    switch self {
                    case .strengthening(let pct): return "Long-term growth: \(String(format: "+%.1f%%", pct))"
                    case .plateaued: return "Maintaining baseline"
                    case .weakening(let pct): return "Long-term decline: \(String(format: "%.1f%%", pct))"
                    }
                }
            }
            
            struct PeakPeriod {
                let startDate: Date
                let endDate: Date
                let averagePerformance: Double
                let reason: String
            }
        }
        
        struct TemporalSynthesis {
            let headline: String
            let insights: [String]
            let recommendation: String
            let confidence: StatisticalResult.ConfidenceLevel
        }
    }
    
    // MARK: - Analyze Temporal Patterns
    
    func analyzeTemporalPatterns(
        workouts: [WorkoutData],
        activityType: String
    ) -> TemporalAnalysis? {
        
        guard !workouts.isEmpty else { return nil }
        
        print("\n🕐 Temporal Analysis for \(activityType)")
        print(String(repeating: "=", count: 50))
        
        // Filter for specific activity
        let filteredWorkouts = workouts.filter { workout in
            switch workout.workoutType {
            case .cycling where activityType == "Ride": return true
            case .running where activityType == "Run": return true
            case .swimming where activityType == "Swim": return true
            default: return false
            }
        }
        
        guard filteredWorkouts.count >= 10 else {
            print("⚠️ Insufficient data (\(filteredWorkouts.count) workouts)")
            return nil
        }
        
        // 1. Recency Analysis (last 30 days)
        let recency = analyzeRecency(workouts: filteredWorkouts)
        
        // 2. Seasonal Analysis (across years)
        let seasonal = analyzeSeasonal(workouts: filteredWorkouts)
        
        // 3. Longitudinal Analysis (multi-year trends)
        let longitudinal = analyzeLongitudinal(workouts: filteredWorkouts)
        
        // 4. Synthesize insights
        let synthesis = synthesizeInsights(
            recency: recency,
            seasonal: seasonal,
            longitudinal: longitudinal
        )
        
        print("✅ Temporal analysis complete")
        print(String(repeating: "=", count: 50) + "\n")
        
        return TemporalAnalysis(
            recency: recency,
            seasonal: seasonal,
            longitudinal: longitudinal,
            synthesis: synthesis
        )
    }
    
    // MARK: - Recency Analysis
    
    private func analyzeRecency(workouts: [WorkoutData]) -> TemporalAnalysis.RecencyAnalysis {
        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now)!
        
        // Recent 30 days
        let recentWorkouts = workouts.filter { $0.startDate >= thirtyDaysAgo }
        
        // Previous 30 days (for comparison)
        let previousWorkouts = workouts.filter {
            $0.startDate >= sixtyDaysAgo && $0.startDate < thirtyDaysAgo
        }
        
        print("📊 Recency Analysis:")
        print("   Recent workouts: \(recentWorkouts.count)")
        print("   Previous period: \(previousWorkouts.count)")
        
        // Calculate current form
        let recentPerf = extractPerformanceMetrics(from: recentWorkouts)
        let previousPerf = extractPerformanceMetrics(from: previousWorkouts)
        
        // Determine trend
        let trend: TemporalAnalysis.RecencyAnalysis.Trend
        if let recent = recentPerf.primary, let previous = previousPerf.primary {
            let change = ((recent - previous) / previous) * 100
            
            if change > 3 {
                trend = .improving(percentChange: change)
            } else if change < -3 {
                trend = .declining(percentChange: change)
            } else {
                trend = .stable
            }
            
            print("   Trend: \(trend.description)")
        } else {
            trend = .stable
        }
        
        // Calculate volatility (coefficient of variation)
        let performances = recentWorkouts.compactMap { extractPerformance(workout: $0) }
        let volatility = calculateVolatility(performances)
        
        let consistency = max(0, 1.0 - volatility)
        print("   Consistency: \(String(format: "%.1f%%", consistency * 100))")
        
        return TemporalAnalysis.RecencyAnalysis(
            currentForm: TemporalAnalysis.RecencyAnalysis.FormMetrics(
                averagePower: recentPerf.power,
                averageSpeed: recentPerf.speed,
                trainingLoad: Double(recentWorkouts.count),
                consistency: consistency
            ),
            trend: trend,
            volatility: volatility,
            timeWindow: "Last 30 days"
        )
    }
    
    // MARK: - Seasonal Analysis
    
    private func analyzeSeasonal(workouts: [WorkoutData]) -> TemporalAnalysis.SeasonalAnalysis {
        var seasonalPerformance: [TemporalAnalysis.SeasonalAnalysis.Season: [Double]] = [:]
        
        for workout in workouts {
            let season = TemporalAnalysis.SeasonalAnalysis.Season.from(date: workout.startDate)
            if let perf = extractPerformance(workout: workout) {
                seasonalPerformance[season, default: []].append(perf)
            }
        }
        
        print("🌍 Seasonal Analysis:")
        
        // Calculate metrics per season
        var seasonMetrics: [TemporalAnalysis.SeasonalAnalysis.Season: TemporalAnalysis.SeasonalAnalysis.SeasonMetrics] = [:]
        
        for season in TemporalAnalysis.SeasonalAnalysis.Season.allCases {
            if let performances = seasonalPerformance[season], !performances.isEmpty {
                let avg = performances.reduce(0, +) / Double(performances.count)
                
                let confidence: StatisticalResult.ConfidenceLevel
                if performances.count >= 30 {
                    confidence = .high
                } else if performances.count >= 10 {
                    confidence = .medium
                } else {
                    confidence = .low
                }
                
                seasonMetrics[season] = TemporalAnalysis.SeasonalAnalysis.SeasonMetrics(
                    season: season,
                    averagePerformance: avg,
                    sampleSize: performances.count,
                    confidence: confidence
                )
                
                print("   \(season.emoji) \(season.rawValue): \(String(format: "%.1f", avg)) (n=\(performances.count))")
            }
        }
        
        // Find best season
        let bestSeason = seasonMetrics.max(by: { $0.value.averagePerformance < $1.value.averagePerformance })?.key ?? .summer
        
        // Current season
        let currentSeason = TemporalAnalysis.SeasonalAnalysis.Season.from(date: Date())
        let currentSeasonMetrics = seasonMetrics[currentSeason] ?? TemporalAnalysis.SeasonalAnalysis.SeasonMetrics(
            season: currentSeason,
            averagePerformance: 0,
            sampleSize: 0,
            confidence: .insufficient
        )
        
        // Year-over-year change
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date())!
        let lastYearSeason = TemporalAnalysis.SeasonalAnalysis.Season.from(date: oneYearAgo)
        
        let yearOverYear: Double?
        if let currentPerf = seasonMetrics[currentSeason]?.averagePerformance,
           let lastYearPerf = seasonMetrics[lastYearSeason]?.averagePerformance {
            yearOverYear = ((currentPerf - lastYearPerf) / lastYearPerf) * 100
            print("   📅 YoY Change: \(String(format: "%+.1f%%", yearOverYear ?? 0))")
        } else {
            yearOverYear = nil
        }
        
        return TemporalAnalysis.SeasonalAnalysis(
            currentSeasonPerformance: currentSeasonMetrics,
            bestSeason: bestSeason,
            seasonalPattern: seasonMetrics,
            yearOverYearChange: yearOverYear
        )
    }
    
    // MARK: - Longitudinal Analysis
    
    private func analyzeLongitudinal(workouts: [WorkoutData]) -> TemporalAnalysis.LongitudinalAnalysis {
        // Determine primary metric type
        let hasPower = workouts.contains { $0.averagePower != nil && $0.averagePower! > 0 }
        
        let relevantWorkouts: [WorkoutData]
        let metricType: String
        
        if hasPower {
            // Get all workouts with power AND heart rate
            let powerHRWorkouts = workouts.filter { workout in
                guard let power = workout.averagePower, power > 0 else { return false }
                guard let hr = workout.averageHeartRate, hr > 0 else { return false }
                return true
            }
            
            // Calculate athlete's typical HR distribution
            let heartRates = powerHRWorkouts.compactMap { $0.averageHeartRate }
            
            if heartRates.isEmpty {
                // Fallback if no HR data - use all power workouts
                relevantWorkouts = workouts.filter { $0.averagePower != nil && $0.averagePower! > 0 }
                metricType = "Power (W)"
                print("\n🔍 LONGITUDINAL DEBUG:")
                print("   Total workouts: \(workouts.count)")
                print("   Metric type: \(metricType)")
                print("   Relevant workouts: \(relevantWorkouts.count)")
                print("   ⚠️ No HR data - using all power workouts")
            } else {
                // Find 60th percentile HR - focuses on harder efforts
                let sortedHRs = heartRates.sorted()
                let percentile60Index = Int(Double(sortedHRs.count) * 0.60)
                let hrThreshold = sortedHRs[percentile60Index]
                
                // Only analyze workouts above 60th percentile HR
                // This automatically filters out easy rides while adapting to athlete
                relevantWorkouts = powerHRWorkouts.filter { workout in
                    guard let hr = workout.averageHeartRate else { return false }
                    return hr >= hrThreshold
                }
                
                metricType = "Power (W)"
                
                print("\n🔍 LONGITUDINAL DEBUG:")
                print("   Total workouts: \(workouts.count)")
                print("   Workouts with Power + HR: \(powerHRWorkouts.count)")
                print("   60th percentile HR: \(Int(hrThreshold)) bpm")
                print("   Metric type: \(metricType)")
                print("   Relevant workouts (≥60th %ile HR): \(relevantWorkouts.count)")
            }
            
        } else {
            // Speed-based for runners/swimmers - also filter by HR if available
            let speedHRWorkouts = workouts.filter { workout in
                guard let dist = workout.totalDistance, dist > 0, workout.duration > 0 else { return false }
                guard let hr = workout.averageHeartRate, hr > 0 else { return false }
                return true
            }
            
            if !speedHRWorkouts.isEmpty {
                // Apply same 60th percentile HR filter for runners/swimmers
                let heartRates = speedHRWorkouts.compactMap { $0.averageHeartRate }
                let sortedHRs = heartRates.sorted()
                let percentile60Index = Int(Double(sortedHRs.count) * 0.60)
                let hrThreshold = sortedHRs[percentile60Index]
                
                relevantWorkouts = speedHRWorkouts.filter { workout in
                    guard let hr = workout.averageHeartRate else { return false }
                    return hr >= hrThreshold
                }
                
                metricType = "Speed (mph)"
                
                print("\n🔍 LONGITUDINAL DEBUG:")
                print("   Total workouts: \(workouts.count)")
                print("   Workouts with Speed + HR: \(speedHRWorkouts.count)")
                print("   60th percentile HR: \(Int(hrThreshold)) bpm")
                print("   Metric type: \(metricType)")
                print("   Relevant workouts (≥60th %ile HR): \(relevantWorkouts.count)")
            } else {
                // Fallback - use all workouts with speed
                relevantWorkouts = workouts.filter { workout in
                    guard let dist = workout.totalDistance, dist > 0, workout.duration > 0 else { return false }
                    return true
                }
                
                metricType = "Speed (mph)"
                
                print("\n🔍 LONGITUDINAL DEBUG:")
                print("   Total workouts: \(workouts.count)")
                print("   Metric type: \(metricType)")
                print("   Relevant workouts: \(relevantWorkouts.count)")
                print("   ⚠️ No HR data - using all workouts")
            }
        }
        
        let sortedWorkouts = relevantWorkouts.sorted { $0.startDate < $1.startDate }
        
        guard let firstDate = sortedWorkouts.first?.startDate,
              let lastDate = sortedWorkouts.last?.startDate else {
            return TemporalAnalysis.LongitudinalAnalysis(
                overallTrend: .plateaued,
                peakPeriods: [],
                growthRate: 0,
                timespan: "Insufficient data"
            )
        }
        
        let calendar = Calendar.current
        let years = calendar.dateComponents([.year], from: firstDate, to: lastDate).year ?? 0
        
        print("📈 Longitudinal Analysis:")
        print("   Timespan: \(years) years")
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        print("   First workout: \(formatter.string(from: firstDate))")
        print("   Last workout: \(formatter.string(from: lastDate))")
        
        // Split into early vs late periods
        let midpoint = firstDate.addingTimeInterval(lastDate.timeIntervalSince(firstDate) / 2)
        
        let earlyWorkouts = sortedWorkouts.filter { $0.startDate < midpoint }
        let lateWorkouts = sortedWorkouts.filter { $0.startDate >= midpoint }
        
        print("\n   Early period workouts: \(earlyWorkouts.count)")
        print("   Late period workouts: \(lateWorkouts.count)")
        
        let earlyPerf = extractPerformanceMetrics(from: earlyWorkouts)
        let latePerf = extractPerformanceMetrics(from: lateWorkouts)
        
        // DEBUG: Show what we're comparing
        print("\n   EARLY PERIOD METRICS:")
        if let power = earlyPerf.power {
            print("      Power: \(String(format: "%.1fW", power))")
        }
        if let speed = earlyPerf.speed {
            print("      Speed: \(String(format: "%.1f mph", speed))")
        }
        print("      Primary metric: \(earlyPerf.primary != nil ? String(format: "%.1f", earlyPerf.primary!) : "none")")
        
        print("\n   LATE PERIOD METRICS:")
        if let power = latePerf.power {
            print("      Power: \(String(format: "%.1fW", power))")
        }
        if let speed = latePerf.speed {
            print("      Speed: \(String(format: "%.1f mph", speed))")
        }
        print("      Primary metric: \(latePerf.primary != nil ? String(format: "%.1f", latePerf.primary!) : "none")")
        
        // Calculate overall trend (only if comparing same metric type)
        let trend: TemporalAnalysis.LongitudinalAnalysis.LongTermTrend
        let growthRate: Double
        
        // Only compare if we have the same metric type in both periods
        let canCompare = (earlyPerf.power != nil && latePerf.power != nil) ||
                         (earlyPerf.power == nil && latePerf.power == nil)
        
        if canCompare,
           let early = earlyPerf.primary,
           let late = latePerf.primary,
           years > 0 {
            let totalChange = ((late - early) / early) * 100
            
            // Cap extreme values (likely data quality issues)
            let cappedChange = min(max(totalChange, -90), 200)
            growthRate = cappedChange / Double(years)
            
            print("\n   COMPARISON:")
            print("      Early avg: \(String(format: "%.1f", early))")
            print("      Late avg: \(String(format: "%.1f", late))")
            print("      Total change: \(String(format: "%+.1f%%", totalChange))")
            print("      Capped change: \(String(format: "%+.1f%%", cappedChange))")
            print("      Annual growth: \(String(format: "%+.1f%%", growthRate))")
            
            if cappedChange > 10 {
                trend = .strengthening(percentChange: cappedChange)
            } else if cappedChange < -10 {
                trend = .weakening(percentChange: cappedChange)
            } else {
                trend = .plateaued
            }
        } else {
            print("\n   ⚠️ Cannot compare - metric type changed over time")
            trend = .plateaued
            growthRate = 0
        }
        
        // Find peak periods (rolling 90-day windows)
        let peakPeriods = findPeakPeriods(workouts: sortedWorkouts)
        print("   Peak periods found: \(peakPeriods.count)")
        
        return TemporalAnalysis.LongitudinalAnalysis(
            overallTrend: trend,
            peakPeriods: peakPeriods,
            growthRate: growthRate,
            timespan: "\(formatter.string(from: firstDate)) - \(formatter.string(from: lastDate))"
        )
    }
    
    // MARK: - Synthesis
    
    private func synthesizeInsights(
        recency: TemporalAnalysis.RecencyAnalysis,
        seasonal: TemporalAnalysis.SeasonalAnalysis,
        longitudinal: TemporalAnalysis.LongitudinalAnalysis
    ) -> TemporalAnalysis.TemporalSynthesis {
        
        var insights: [String] = []
        
        // Recency insight
        switch recency.trend {
        case .improving(let pct):
            insights.append("Recent form is improving (\(String(format: "+%.1f%%", pct)) over last 30 days)")
        case .declining(let pct):
            insights.append("Recent form is declining (\(String(format: "%.1f%%", pct)) over last 30 days)")
        case .stable:
            insights.append("Recent form is stable")
        }
        
        // Seasonal insight
        if let yoy = seasonal.yearOverYearChange {
            insights.append("Year-over-year: \(String(format: "%+.1f%%", yoy))")
        }
        
        if seasonal.bestSeason != seasonal.currentSeasonPerformance.season {
            insights.append("Historically strongest in \(seasonal.bestSeason.emoji) \(seasonal.bestSeason.rawValue)")
        }
        
        // Longitudinal insight
        insights.append(longitudinal.overallTrend.description)
        
        // Generate headline
        let headline: String
        switch (recency.trend, longitudinal.overallTrend) {
        case (.improving, .strengthening):
            headline = "Building on Strong Foundation"
        case (.improving, _):
            headline = "Current Form is Rising"
        case (.declining, .strengthening):
            headline = "Recent Dip in Long-term Growth"
        case (.declining, _):
            headline = "Managing Current Decline"
        case (.stable, .strengthening):
            headline = "Sustaining Long-term Progress"
        default:
            headline = "Maintaining Current Form"
        }
        
        // Generate recommendation
        let recommendation: String
        if case .declining = recency.trend {
            recommendation = "Consider a recovery week to restore form"
        } else if case .improving = recency.trend {
            recommendation = "Maintain current training approach"
        } else {
            recommendation = "Gradually increase load to progress"
        }
        
        // Overall confidence
        let confidence: StatisticalResult.ConfidenceLevel = seasonal.currentSeasonPerformance.confidence
        
        return TemporalAnalysis.TemporalSynthesis(
            headline: headline,
            insights: insights,
            recommendation: recommendation,
            confidence: confidence
        )
    }
    
    // MARK: - Helper Functions
    
    private struct PerformanceMetrics {
        let power: Double?
        let speed: Double?
        let primary: Double?
    }
    
    private func extractPerformanceMetrics(from workouts: [WorkoutData]) -> PerformanceMetrics {
        let powers = workouts.compactMap { $0.averagePower }.filter { $0 > 0 }
        let speeds = workouts.compactMap { workout -> Double? in
            guard let dist = workout.totalDistance, dist > 0, workout.duration > 0 else { return nil }
            return (dist / workout.duration) * 2.23694 // mph
        }
        
        let avgPower = powers.isEmpty ? nil : powers.reduce(0, +) / Double(powers.count)
        let avgSpeed = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
        
        return PerformanceMetrics(
            power: avgPower,
            speed: avgSpeed,
            primary: avgPower ?? avgSpeed
        )
    }
    
    private func extractPerformance(workout: WorkoutData) -> Double? {
        if let power = workout.averagePower, power > 0 {
            return power
        }
        
        if let dist = workout.totalDistance, dist > 0, workout.duration > 0 {
            return (dist / workout.duration) * 2.23694
        }
        
        return nil
    }
    
    private func calculateVolatility(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        let stdDev = sqrt(variance)
        
        return mean > 0 ? stdDev / mean : 0
    }
    
    private func findPeakPeriods(workouts: [WorkoutData]) -> [TemporalAnalysis.LongitudinalAnalysis.PeakPeriod] {
        var peaks: [TemporalAnalysis.LongitudinalAnalysis.PeakPeriod] = []
        
        // Use rolling 90-day windows
        let calendar = Calendar.current
        let sortedWorkouts = workouts.sorted { $0.startDate < $1.startDate }
        
        guard let firstDate = sortedWorkouts.first?.startDate,
              let lastDate = sortedWorkouts.last?.startDate else {
            return []
        }
        
        var currentDate = firstDate
        var windowPerformances: [(start: Date, end: Date, performance: Double)] = []
        
        while currentDate < lastDate {
            let windowEnd = calendar.date(byAdding: .day, value: 90, to: currentDate)!
            let windowWorkouts = sortedWorkouts.filter {
                $0.startDate >= currentDate && $0.startDate < windowEnd
            }
            
            if windowWorkouts.count >= 5 {
                let perf = extractPerformanceMetrics(from: windowWorkouts)
                if let primary = perf.primary {
                    windowPerformances.append((currentDate, windowEnd, primary))
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 30, to: currentDate)!
        }
        
        // Find top 3 windows
        let topWindows = windowPerformances.sorted { $0.performance > $1.performance }.prefix(3)
        
        for window in topWindows {
            peaks.append(TemporalAnalysis.LongitudinalAnalysis.PeakPeriod(
                startDate: window.start,
                endDate: window.end,
                averagePerformance: window.performance,
                reason: "High performance period"
            ))
        }
        
        return peaks
    }
}
