//
//  CorrelationEngine.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import HealthKit

class CorrelationEngine {
    
    // MARK: - Sleep vs Performance Analysis
    
    struct SleepPerformanceInsight {
        let averagePerformanceWithGoodSleep: Double  // 7+ hours
        let averagePerformanceWithPoorSleep: Double  // <7 hours
        let performanceDifferencePercent: Double
        let sampleSize: Int
        let confidence: ConfidenceLevel
        
        enum ConfidenceLevel {
            case high    // 20+ data points
            case medium  // 10-19 data points
            case low     // 5-9 data points
            case insufficient // <5 data points
            
            var description: String {
                switch self {
                case .high: return "High confidence"
                case .medium: return "Medium confidence"
                case .low: return "Low confidence"
                case .insufficient: return "More data needed"
                }
            }
        }
        
        var insightText: String {
            if confidence == .insufficient {
                return "Not enough data yet. Keep tracking to see how sleep affects your performance!"
            }
            
            // Check for meaningful difference (at least 5%)
            if abs(performanceDifferencePercent) < 5.0 {
                return "Sleep duration doesn't show a strong correlation with performance yet (\(confidence.description))"
            }
            
            let direction = performanceDifferencePercent > 0 ? "better" : "worse"
            let percent = abs(performanceDifferencePercent)
            
            return "You perform \(String(format: "%.1f", percent))% \(direction) on days after 7+ hours of sleep (\(confidence.description))"
        }
    }
    
    // MARK: - Activity-Specific Insights
    
    struct ActivityTypeInsight {
        let activityType: String
        let goodSleepAvg: Double
        let poorSleepAvg: Double
        let percentDifference: Double
        let sampleSize: Int
    }
    
    /// Analyzes sleep vs performance separately for each activity type
    func analyzeSleepVsPerformanceByActivityType(
        sleepData: [HealthDataPoint],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> [ActivityTypeInsight] {
        
        // Deduplicate workouts
        let (hkOnly, stravaOnly, matched) = WorkoutMatcher.deduplicateWorkouts(
            healthKitWorkouts: healthKitWorkouts,
            stravaActivities: stravaActivities
        )
        
        // Create a dictionary of sleep by date
        var sleepByDate: [Date: Double] = [:]
        let calendar = Calendar.current
        
        for sleep in sleepData {
            let dayStart = calendar.startOfDay(for: sleep.date)
            sleepByDate[dayStart] = sleep.value
        }
        
        // Group performance by activity type
        var performanceByType: [String: (good: [Double], poor: [Double])] = [:]
        
        // Process Strava-only activities
        for activity in stravaOnly {
            if let metric = processStravaActivity(activity, sleepByDate: sleepByDate, calendar: calendar) {
                let type = activity.type
                if performanceByType[type] == nil {
                    performanceByType[type] = (good: [], poor: [])
                }
                
                if metric.sleepHours >= 7.0 {
                    performanceByType[type]?.good.append(metric.performance)
                } else {
                    performanceByType[type]?.poor.append(metric.performance)
                }
            }
        }
        
        // Process HealthKit-only workouts
        for workout in hkOnly {
            if let metric = processHealthKitWorkout(workout, sleepByDate: sleepByDate, calendar: calendar) {
                let type = workout.workoutType.name
                if performanceByType[type] == nil {
                    performanceByType[type] = (good: [], poor: [])
                }
                
                if metric.sleepHours >= 7.0 {
                    performanceByType[type]?.good.append(metric.performance)
                } else {
                    performanceByType[type]?.poor.append(metric.performance)
                }
            }
        }
        
        // Process matched workouts (prefer Strava)
        for (_, stravaActivity) in matched {
            if let metric = processStravaActivity(stravaActivity, sleepByDate: sleepByDate, calendar: calendar) {
                let type = stravaActivity.type
                if performanceByType[type] == nil {
                    performanceByType[type] = (good: [], poor: [])
                }
                
                if metric.sleepHours >= 7.0 {
                    performanceByType[type]?.good.append(metric.performance)
                } else {
                    performanceByType[type]?.poor.append(metric.performance)
                }
            }
        }
        
        // Calculate insights for each activity type
        var insights: [ActivityTypeInsight] = []
        
        for (type, data) in performanceByType {
            let totalSamples = data.good.count + data.poor.count
            
            print("📊 \(type):")
            print("   Good sleep: \(data.good.count) workouts")
            print("   Poor sleep: \(data.poor.count) workouts")
            print("   Total: \(totalSamples)")
            
            // Need at least 5 total samples AND at least 2 in each category
            guard totalSamples >= 5, data.good.count >= 2, data.poor.count >= 2 else {
                print("   ⚠️ Not enough data for meaningful analysis")
                continue
            }
            
            let avgGood = data.good.reduce(0, +) / Double(data.good.count)
            let avgPoor = data.poor.reduce(0, +) / Double(data.poor.count)
            
            let baseline = max(avgGood, avgPoor)
            let percentDiff = baseline > 0 ? ((avgGood - avgPoor) / baseline) * 100 : 0
            
            // Only include if difference is meaningful (>5%)
            if abs(percentDiff) >= 5.0 {
                insights.append(ActivityTypeInsight(
                    activityType: type,
                    goodSleepAvg: avgGood,
                    poorSleepAvg: avgPoor,
                    percentDifference: percentDiff,
                    sampleSize: data.good.count + data.poor.count
                ))
                
                print("📊 \(type) Sleep Analysis:")
                print("   Good sleep: \(data.good.count) workouts, avg \(String(format: "%.1f", avgGood))")
                print("   Poor sleep: \(data.poor.count) workouts, avg \(String(format: "%.1f", avgPoor))")
                print("   Difference: \(String(format: "%.1f", percentDiff))%")
            }
        }
        
        return insights.sorted { abs($0.percentDifference) > abs($1.percentDifference) }
    }
    
    /// Analyzes correlation between sleep and performance using both HealthKit and Strava data
    /// This version deduplicates workouts that exist in both sources
    func analyzeSleepVsPerformanceCombined(
        sleepData: [HealthDataPoint],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> SleepPerformanceInsight? {
        
        // Deduplicate workouts
        let (hkOnly, stravaOnly, matched) = WorkoutMatcher.deduplicateWorkouts(
            healthKitWorkouts: healthKitWorkouts,
            stravaActivities: stravaActivities
        )
        
        print("📊 Sleep vs Performance Analysis:")
        print("   Using \(hkOnly.count) HealthKit-only workouts")
        print("   Using \(stravaOnly.count) Strava-only workouts")
        print("   Using \(matched.count) matched workouts (counted once)")
        
        // Create a dictionary of sleep by date
        var sleepByDate: [Date: Double] = [:]
        let calendar = Calendar.current
        
        for sleep in sleepData {
            let dayStart = calendar.startOfDay(for: sleep.date)
            sleepByDate[dayStart] = sleep.value
        }
        
        var goodSleepWorkouts: [Double] = []
        var poorSleepWorkouts: [Double] = []
        
        // Process Strava-only activities
        for activity in stravaOnly {
            if let performanceMetric = processStravaActivity(activity, sleepByDate: sleepByDate, calendar: calendar) {
                if performanceMetric.sleepHours >= 7.0 {
                    goodSleepWorkouts.append(performanceMetric.performance)
                } else {
                    poorSleepWorkouts.append(performanceMetric.performance)
                }
            }
        }
        
        // Process HealthKit-only workouts
        for workout in hkOnly {
            if let performanceMetric = processHealthKitWorkout(workout, sleepByDate: sleepByDate, calendar: calendar) {
                if performanceMetric.sleepHours >= 7.0 {
                    goodSleepWorkouts.append(performanceMetric.performance)
                } else {
                    poorSleepWorkouts.append(performanceMetric.performance)
                }
            }
        }
        
        // Process matched workouts (prefer Strava data as it's usually more detailed)
        for (_, stravaActivity) in matched {
            if let performanceMetric = processStravaActivity(stravaActivity, sleepByDate: sleepByDate, calendar: calendar) {
                if performanceMetric.sleepHours >= 7.0 {
                    goodSleepWorkouts.append(performanceMetric.performance)
                } else {
                    poorSleepWorkouts.append(performanceMetric.performance)
                }
            }
        }
        
        // Need at least 5 workouts total AND at least 3 in each category for meaningful comparison
        let totalSamples = goodSleepWorkouts.count + poorSleepWorkouts.count
        
        if totalSamples < 5 || goodSleepWorkouts.count < 3 || poorSleepWorkouts.count < 3 {
            print("⚠️ Insufficient data for meaningful comparison:")
            print("   Good sleep: \(goodSleepWorkouts.count), Poor sleep: \(poorSleepWorkouts.count)")
            
            return SleepPerformanceInsight(
                averagePerformanceWithGoodSleep: 0,
                averagePerformanceWithPoorSleep: 0,
                performanceDifferencePercent: 0,
                sampleSize: totalSamples,
                confidence: .insufficient
            )
        }
        
        // Calculate averages
        let avgGoodSleep = goodSleepWorkouts.isEmpty ? 0 : goodSleepWorkouts.reduce(0, +) / Double(goodSleepWorkouts.count)
        let avgPoorSleep = poorSleepWorkouts.isEmpty ? 0 : poorSleepWorkouts.reduce(0, +) / Double(poorSleepWorkouts.count)
        
        // Calculate percentage difference
        let baseline = max(avgGoodSleep, avgPoorSleep)
        let percentDifference = baseline > 0 ? ((avgGoodSleep - avgPoorSleep) / baseline) * 100 : 0
        
        // DEBUG SECTION:
        print("📊 Sleep Performance Details:")
        print("   Good sleep workouts: \(goodSleepWorkouts.count)")
        print("   Poor sleep workouts: \(poorSleepWorkouts.count)")
        print("   Avg performance (good sleep): \(String(format: "%.2f", avgGoodSleep))")
        print("   Avg performance (poor sleep): \(String(format: "%.2f", avgPoorSleep))")
        print("   Difference: \(String(format: "%.1f", percentDifference))%")
        
        if !goodSleepWorkouts.isEmpty {
            print("   Good sleep samples: \(goodSleepWorkouts.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
        }
        if !poorSleepWorkouts.isEmpty {
            print("   Poor sleep samples: \(poorSleepWorkouts.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
        }
        
        // Determine confidence level
        let confidence: SleepPerformanceInsight.ConfidenceLevel
        if totalSamples >= 20 {
            confidence = .high
        } else if totalSamples >= 10 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        return SleepPerformanceInsight(
            averagePerformanceWithGoodSleep: avgGoodSleep,
            averagePerformanceWithPoorSleep: avgPoorSleep,
            performanceDifferencePercent: percentDifference,
            sampleSize: totalSamples,
            confidence: confidence
        )
    }
    
    // MARK: - Helper Methods
    
    private struct PerformanceMetric {
        let performance: Double
        let sleepHours: Double
    }
    
    private func processStravaActivity(
        _ activity: StravaActivity,
        sleepByDate: [Date: Double],
        calendar: Calendar
    ) -> PerformanceMetric? {
        
        guard let workoutDate = activity.startDateFormatted else { return nil }
        
        // Only analyze running/cycling activities with pace data
        guard activity.type == "Run" || activity.type == "Ride" else { return nil }
        guard let avgSpeed = activity.averageSpeed, avgSpeed > 0 else { return nil }
        
        // Get previous night's sleep
        let workoutDay = calendar.startOfDay(for: workoutDate)
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: workoutDay),
              let sleepHours = sleepByDate[previousDay] else { return nil }
        
        // Calculate performance metric
        let performanceMetric: Double
        if activity.type == "Run" {
            performanceMetric = avgSpeed * 2.23694 // m/s to mph
        } else {
            performanceMetric = activity.averageWatts ?? (avgSpeed * 2.23694)
        }
        
        return PerformanceMetric(performance: performanceMetric, sleepHours: sleepHours)
    }
    
    private func processHealthKitWorkout(
        _ workout: WorkoutData,
        sleepByDate: [Date: Double],
        calendar: Calendar
    ) -> PerformanceMetric? {
        
        // Only process cardio workouts
        let cardioTypes: [HKWorkoutActivityType] = [.running, .cycling, .walking, .hiking]
        guard cardioTypes.contains(workout.workoutType) else { return nil }
        
        // Need distance to calculate pace/speed
        guard let distance = workout.totalDistance, distance > 0, workout.duration > 0 else { return nil }
        
        // Get previous night's sleep
        let workoutDay = calendar.startOfDay(for: workout.startDate)
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: workoutDay),
              let sleepHours = sleepByDate[previousDay] else { return nil }
        
        // Calculate speed in mph
        let speedMPS = distance / workout.duration // meters per second
        let speedMPH = speedMPS * 2.23694
        
        return PerformanceMetric(performance: speedMPH, sleepHours: sleepHours)
    }
    
    /// Get summary of available data for progress tracking
    func getDataSummary(
        sleepData: [HealthDataPoint],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> [(activityType: String, goodSleep: Int, poorSleep: Int)] {
        
        let (hkOnly, stravaOnly, matched) = WorkoutMatcher.deduplicateWorkouts(
            healthKitWorkouts: healthKitWorkouts,
            stravaActivities: stravaActivities
        )
        
        var sleepByDate: [Date: Double] = [:]
        let calendar = Calendar.current
        
        for sleep in sleepData {
            let dayStart = calendar.startOfDay(for: sleep.date)
            sleepByDate[dayStart] = sleep.value
        }
        
        var countsByType: [String: (good: Int, poor: Int)] = [:]
        
        // Process all workouts
        let allWorkouts = stravaOnly.compactMap { activity -> (String, Double)? in
            guard let metric = processStravaActivity(activity, sleepByDate: sleepByDate, calendar: calendar) else { return nil }
            return (activity.type, metric.sleepHours)
        } + hkOnly.compactMap { workout -> (String, Double)? in
            guard let metric = processHealthKitWorkout(workout, sleepByDate: sleepByDate, calendar: calendar) else { return nil }
            return (workout.workoutType.name, metric.sleepHours)
        } + matched.compactMap { (_, activity) -> (String, Double)? in
            guard let metric = processStravaActivity(activity, sleepByDate: sleepByDate, calendar: calendar) else { return nil }
            return (activity.type, metric.sleepHours)
        }
        
        for (type, sleepHours) in allWorkouts {
            if countsByType[type] == nil {
                countsByType[type] = (good: 0, poor: 0)
            }
            
            if sleepHours >= 7.0 {
                countsByType[type]?.good += 1
            } else {
                countsByType[type]?.poor += 1
            }
        }
        
        return countsByType.map { (activityType: $0.key, goodSleep: $0.value.good, poorSleep: $0.value.poor) }
            .sorted { $0.goodSleep + $0.poorSleep > $1.goodSleep + $1.poorSleep }
    }
    
    // MARK: - Simple Insights (No Comparison Needed)
    
    struct SimpleInsight {
        let title: String
        let value: String
        let description: String
        let icon: String
        let iconColor: String
    }
    
    /// Generate simple insights from available data
    func generateSimpleInsights(
        sleepData: [HealthDataPoint],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity],
        restingHRData: [HealthDataPoint],
        hrvData: [HealthDataPoint]
    ) -> [SimpleInsight] {
        
        var insights: [SimpleInsight] = []
        
        // Sleep consistency
        if sleepData.count >= 7 {
            let avgSleep = sleepData.map { $0.value }.reduce(0, +) / Double(sleepData.count)
            let sleepValues = sleepData.map { $0.value }
            let variance = sleepValues.map { pow($0 - avgSleep, 2) }.reduce(0, +) / Double(sleepValues.count)
            let stdDev = sqrt(variance)
            
            let consistency = stdDev < 1.0 ? "very consistent" : stdDev < 1.5 ? "fairly consistent" : "variable"
            
            insights.append(SimpleInsight(
                title: "Sleep Consistency",
                value: String(format: "%.1f hrs avg", avgSleep),
                description: "Your sleep is \(consistency) (±\(String(format: "%.1f", stdDev)) hrs)",
                icon: "bed.double.fill",
                iconColor: "blue"
            ))
        }
        
        // Workout frequency
        let totalWorkouts = healthKitWorkouts.count + stravaActivities.count
        if totalWorkouts > 0 {
            let days = 30
            let workoutsPerWeek = Double(totalWorkouts) / Double(days) * 7.0
            
            insights.append(SimpleInsight(
                title: "Training Frequency",
                value: String(format: "%.1f/week", workoutsPerWeek),
                description: "\(totalWorkouts) workouts in the last 30 days",
                icon: "figure.run",
                iconColor: "orange"
            ))
        }
        
        // Resting HR trend
        if restingHRData.count >= 7 {
            let recent = Array(restingHRData.suffix(7))
            let older = Array(restingHRData.prefix(min(7, restingHRData.count - 7)))
            
            if !older.isEmpty {
                let recentAvg = recent.map { $0.value }.reduce(0, +) / Double(recent.count)
                let olderAvg = older.map { $0.value }.reduce(0, +) / Double(older.count)
                let change = recentAvg - olderAvg
                
                let trend = abs(change) < 2 ? "stable" : change < 0 ? "improving" : "elevated"
                
                insights.append(SimpleInsight(
                    title: "Resting Heart Rate",
                    value: String(format: "%.0f bpm", recentAvg),
                    description: "Trend is \(trend) (\(change > 0 ? "+" : "")\(String(format: "%.1f", change)) bpm vs. earlier)",
                    icon: "heart.fill",
                    iconColor: "red"
                ))
            }
        }
        
        // HRV trend
        if hrvData.count >= 7 {
            let recent = Array(hrvData.suffix(7))
            let avgHRV = recent.map { $0.value }.reduce(0, +) / Double(recent.count)
            
            insights.append(SimpleInsight(
                title: "Recovery Status",
                value: String(format: "%.0f ms", avgHRV),
                description: "Your average HRV over the last week",
                icon: "waveform.path.ecg",
                iconColor: "green"
            ))
        }
        
        return insights
    }
    
    // MARK: - HRV vs Performance Analysis
    
    struct HRVPerformanceInsight {
        let activityType: String
        let highHRVAvg: Double      // HRV > personal average
        let lowHRVAvg: Double       // HRV < personal average
        let percentDifference: Double
        let sampleSize: Int
        let confidence: SleepPerformanceInsight.ConfidenceLevel
        
        var insightText: String {
            if confidence == .insufficient {
                return "Not enough data yet. Keep tracking!"
            }
            
            if abs(percentDifference) < 5.0 {
                return "HRV doesn't show a strong correlation with \(activityType.lowercased()) performance yet"
            }
            
            let direction = percentDifference > 0 ? "better" : "worse"
            let percent = abs(percentDifference)
            
            return "Your \(activityType.lowercased()) performance is \(String(format: "%.1f", percent))% \(direction) when HRV is above your baseline"
        }
    }
    
    /// Analyzes correlation between HRV and workout performance by activity type
    func analyzeHRVVsPerformance(
        hrvData: [HealthDataPoint],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> [HRVPerformanceInsight] {
        
        // Calculate average HRV as baseline
        guard !hrvData.isEmpty else { return [] }
        let avgHRV = hrvData.map { $0.value }.reduce(0, +) / Double(hrvData.count)
        
        print("📊 HRV Baseline: \(String(format: "%.1f", avgHRV)) ms")
        
        // Create HRV lookup by date
        var hrvByDate: [Date: Double] = [:]
        let calendar = Calendar.current
        
        for hrv in hrvData {
            let dayStart = calendar.startOfDay(for: hrv.date)
            hrvByDate[dayStart] = hrv.value
        }
        
        // Deduplicate workouts
        let (hkOnly, stravaOnly, matched) = WorkoutMatcher.deduplicateWorkouts(
            healthKitWorkouts: healthKitWorkouts,
            stravaActivities: stravaActivities
        )
        
        // Group performance by activity type and HRV status
        var performanceByType: [String: (high: [Double], low: [Double])] = [:]
        
        // Process Strava activities
        for activity in stravaOnly + matched.map({ $0.1 }) {
            guard let workoutDate = activity.startDateFormatted else { continue }
            guard activity.type == "Run" || activity.type == "Ride" else { continue }
            guard let avgSpeed = activity.averageSpeed, avgSpeed > 0 else { continue }
            
            // Get HRV from same day
            let workoutDay = calendar.startOfDay(for: workoutDate)
            guard let dayHRV = hrvByDate[workoutDay] else { continue }
            
            // Calculate performance metric
            let performanceMetric: Double
            if activity.type == "Run" {
                performanceMetric = avgSpeed * 2.23694 // m/s to mph
            } else {
                performanceMetric = activity.averageWatts ?? (avgSpeed * 2.23694)
            }
            
            let type = activity.type
            if performanceByType[type] == nil {
                performanceByType[type] = (high: [], low: [])
            }
            
            // Categorize by HRV relative to baseline
            if dayHRV >= avgHRV {
                performanceByType[type]?.high.append(performanceMetric)
            } else {
                performanceByType[type]?.low.append(performanceMetric)
            }
        }
        
        // Process HealthKit workouts
        for workout in hkOnly {
            guard let metric = processHealthKitWorkout(workout, sleepByDate: [:], calendar: calendar) else { continue }
            
            let workoutDay = calendar.startOfDay(for: workout.startDate)
            guard let dayHRV = hrvByDate[workoutDay] else { continue }
            
            let type = workout.workoutType.name
            if performanceByType[type] == nil {
                performanceByType[type] = (high: [], low: [])
            }
            
            if dayHRV >= avgHRV {
                performanceByType[type]?.high.append(metric.performance)
            } else {
                performanceByType[type]?.low.append(metric.performance)
            }
        }
        
        // Calculate insights
        var insights: [HRVPerformanceInsight] = []
        
        for (type, data) in performanceByType {
            let totalSamples = data.high.count + data.low.count
            guard totalSamples >= 5, data.high.count >= 2, data.low.count >= 2 else { continue }
            
            let avgHigh = data.high.reduce(0, +) / Double(data.high.count)
            let avgLow = data.low.reduce(0, +) / Double(data.low.count)
            
            let baseline = max(avgHigh, avgLow)
            let percentDiff = baseline > 0 ? ((avgHigh - avgLow) / baseline) * 100 : 0
            
            let confidence: SleepPerformanceInsight.ConfidenceLevel
            if totalSamples >= 20 {
                confidence = .high
            } else if totalSamples >= 10 {
                confidence = .medium
            } else {
                confidence = .low
            }
            
            if abs(percentDiff) >= 5.0 {
                insights.append(HRVPerformanceInsight(
                    activityType: type,
                    highHRVAvg: avgHigh,
                    lowHRVAvg: avgLow,
                    percentDifference: percentDiff,
                    sampleSize: totalSamples,
                    confidence: confidence
                ))
                
                print("📊 \(type) HRV Analysis:")
                print("   High HRV: \(data.high.count) workouts, avg \(String(format: "%.1f", avgHigh))")
                print("   Low HRV: \(data.low.count) workouts, avg \(String(format: "%.1f", avgLow))")
                print("   Difference: \(String(format: "%.1f", percentDiff))%")
            }
        }
        
        return insights.sorted { abs($0.percentDifference) > abs($1.percentDifference) }
    }
    
    
    // MARK: - Resting HR Recovery Analysis
    
    struct RecoveryInsight {
        let metric: String
        let currentValue: Double
        let baselineValue: Double
        let trend: RecoveryTrend
        let message: String
        
        enum RecoveryTrend {
            case recovered      // Better than baseline
            case recovering     // Slightly elevated
            case fatigued       // Significantly elevated
            case stable         // Within normal range
            
            var emoji: String {
                switch self {
                case .recovered: return "✅"
                case .recovering: return "🔄"
                case .fatigued: return "⚠️"
                case .stable: return "➡️"
                }
            }
        }
    }
    
    /// Analyzes current recovery status based on resting HR
    func analyzeRecoveryStatus(
        restingHRData: [HealthDataPoint],
        hrvData: [HealthDataPoint]
    ) -> [RecoveryInsight] {
        
        var insights: [RecoveryInsight] = []
        
        // Resting HR Analysis
        if restingHRData.count >= 7 {
            let recent = Array(restingHRData.suffix(3)) // Last 3 days
            let baseline = Array(restingHRData.prefix(restingHRData.count - 3)) // Earlier data
            
            guard !recent.isEmpty, !baseline.isEmpty else { return insights }
            
            let recentAvg = recent.map { $0.value }.reduce(0, +) / Double(recent.count)
            let baselineAvg = baseline.map { $0.value }.reduce(0, +) / Double(baseline.count)
            let difference = recentAvg - baselineAvg
            
            let trend: RecoveryInsight.RecoveryTrend
            let message: String
            
            if difference <= -3 {
                trend = .recovered
                message = "Your resting heart rate is \(String(format: "%.0f", abs(difference))) bpm below baseline - excellent recovery!"
            } else if difference <= -1 {
                trend = .recovered
                message = "Resting heart rate slightly below baseline - good recovery"
            } else if difference <= 2 {
                trend = .stable
                message = "Resting heart rate is stable at baseline"
            } else if difference <= 5 {
                trend = .recovering
                message = "Resting heart rate is \(String(format: "%.0f", difference)) bpm above baseline - consider easy training"
            } else {
                trend = .fatigued
                message = "Resting heart rate is \(String(format: "%.0f", difference)) bpm elevated - prioritize recovery"
            }
            
            insights.append(RecoveryInsight(
                metric: "Resting Heart Rate",
                currentValue: recentAvg,
                baselineValue: baselineAvg,
                trend: trend,
                message: message
            ))
        }
        
        // HRV Analysis
        if hrvData.count >= 7 {
            let recent = Array(hrvData.suffix(3))
            let baseline = Array(hrvData.prefix(hrvData.count - 3))
            
            guard !recent.isEmpty, !baseline.isEmpty else { return insights }
            
            let recentAvg = recent.map { $0.value }.reduce(0, +) / Double(recent.count)
            let baselineAvg = baseline.map { $0.value }.reduce(0, +) / Double(baseline.count)
            let percentDiff = ((recentAvg - baselineAvg) / baselineAvg) * 100
            
            let trend: RecoveryInsight.RecoveryTrend
            let message: String
            
            if percentDiff >= 10 {
                trend = .recovered
                message = "HRV is \(String(format: "%.0f", percentDiff))% above baseline - well recovered!"
            } else if percentDiff >= 5 {
                trend = .recovered
                message = "HRV slightly elevated - good recovery status"
            } else if percentDiff >= -5 {
                trend = .stable
                message = "HRV is stable at baseline"
            } else if percentDiff >= -15 {
                trend = .recovering
                message = "HRV is \(String(format: "%.0f", abs(percentDiff)))% below baseline - monitor recovery"
            } else {
                trend = .fatigued
                message = "HRV significantly suppressed - prioritize rest and recovery"
            }
            
            insights.append(RecoveryInsight(
                metric: "Heart Rate Variability",
                currentValue: recentAvg,
                baselineValue: baselineAvg,
                trend: trend,
                message: message
            ))
        }
        
        return insights
    }
}
