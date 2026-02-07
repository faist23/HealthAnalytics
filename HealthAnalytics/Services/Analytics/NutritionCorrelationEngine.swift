//
//  NutritionCorrelationEngine.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//

import Foundation
import HealthKit

struct NutritionCorrelationEngine {
    
    // MARK: - Protein vs Recovery Analysis
    
    struct ProteinRecoveryInsight {
        let proteinRanges: [ProteinRange]
        let optimalProteinRange: ProteinRange?
        let currentAverage: Double
        let recommendation: String
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
        
        struct ProteinRange {
            let range: String
            let minProtein: Double
            let maxProtein: Double
            let avgHRV: Double?
            let avgRHR: Double?
            let sampleSize: Int
            
            var recoveryScore: Double? {
                // Combine HRV (higher is better) and RHR (lower is better) into single score
                guard let hrv = avgHRV, let rhr = avgRHR else { return nil }
                
                // Normalize: HRV contribution + inverse RHR contribution
                // This is a simple scoring - higher HRV and lower RHR = better recovery
                return hrv - (rhr * 0.5) // Weight RHR less heavily
            }
        }
    }
    
    /// Analyzes correlation between protein intake and recovery metrics
    func analyzeProteinVsRecovery(
        nutritionData: [DailyNutrition],
        restingHRData: [HealthDataPoint],
        hrvData: [HealthDataPoint]
    ) -> ProteinRecoveryInsight? {
        
        // Need at least 10 days with complete data
        let completeNutritionDays = nutritionData.filter { $0.isComplete }
        guard completeNutritionDays.count >= 10 else {
            print("⚠️ Protein analysis: Need 10+ complete nutrition days (have \(completeNutritionDays.count))")
            return ProteinRecoveryInsight(
                proteinRanges: [],
                optimalProteinRange: nil,
                currentAverage: 0,
                recommendation: "Log nutrition for \(10 - completeNutritionDays.count) more days to unlock protein insights.",
                confidence: .insufficient
            )
        }
        
        // Create lookup dictionaries for recovery metrics
        let calendar = Calendar.current
        var rhrByDate: [Date: Double] = [:]
        var hrvByDate: [Date: Double] = [:]
        
        for rhr in restingHRData {
            let day = calendar.startOfDay(for: rhr.date)
            rhrByDate[day] = rhr.value
        }
        
        for hrv in hrvData {
            let day = calendar.startOfDay(for: hrv.date)
            hrvByDate[day] = hrv.value
        }
        
        // Group protein intake into ranges and correlate with NEXT DAY recovery
        var proteinGroups: [String: (protein: [Double], rhr: [Double], hrv: [Double])] = [
            "<100g": ([], [], []),
            "100-130g": ([], [], []),
            "130-160g": ([], [], []),
            ">160g": ([], [], [])
        ]
        
        for nutrition in completeNutritionDays {
            let protein = nutrition.totalProtein
            let nutritionDay = calendar.startOfDay(for: nutrition.date)
            
            // Get NEXT day's recovery metrics
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: nutritionDay),
                  let nextDayRHR = rhrByDate[nextDay],
                  let nextDayHRV = hrvByDate[nextDay] else {
                continue
            }
            
            // Categorize protein intake
            let group: String
            if protein < 100 {
                group = "<100g"
            } else if protein < 130 {
                group = "100-130g"
            } else if protein < 160 {
                group = "130-160g"
            } else {
                group = ">160g"
            }
            
            proteinGroups[group]?.protein.append(protein)
            proteinGroups[group]?.rhr.append(nextDayRHR)
            proteinGroups[group]?.hrv.append(nextDayHRV)
        }
        
        // Calculate averages for each group
        var ranges: [ProteinRecoveryInsight.ProteinRange] = []
        
        for (groupName, data) in proteinGroups.sorted(by: { $0.key < $1.key }) {
            guard !data.protein.isEmpty else { continue }
            
            let avgRHR = data.rhr.reduce(0, +) / Double(data.rhr.count)
            let avgHRV = data.hrv.reduce(0, +) / Double(data.hrv.count)
            
            let (minP, maxP): (Double, Double)
            switch groupName {
            case "<100g": (minP, maxP) = (0, 100)
            case "100-130g": (minP, maxP) = (100, 130)
            case "130-160g": (minP, maxP) = (130, 160)
            case ">160g": (minP, maxP) = (160, 300)
            default: continue
            }
            
            ranges.append(ProteinRecoveryInsight.ProteinRange(
                range: groupName,
                minProtein: minP,
                maxProtein: maxP,
                avgHRV: avgHRV,
                avgRHR: avgRHR,
                sampleSize: data.protein.count
            ))
        }
        
        // Find optimal range (best recovery score)
        let optimalRange = ranges.max { a, b in
            (a.recoveryScore ?? 0) < (b.recoveryScore ?? 0)
        }
        
        // Current average protein
        let currentAvgProtein = completeNutritionDays.map { $0.totalProtein }.reduce(0, +) / Double(completeNutritionDays.count)
        
        // Determine confidence
        let totalSamples = ranges.reduce(0) { $0 + $1.sampleSize }
        let confidence: ProteinRecoveryInsight.ConfidenceLevel
        if totalSamples >= 20 {
            confidence = .high
        } else if totalSamples >= 10 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        // Generate recommendation
        let recommendation = generateProteinRecommendation(
            optimalRange: optimalRange,
            currentAverage: currentAvgProtein,
            ranges: ranges
        )
        
        return ProteinRecoveryInsight(
            proteinRanges: ranges,
            optimalProteinRange: optimalRange,
            currentAverage: currentAvgProtein,
            recommendation: recommendation,
            confidence: confidence
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateProteinRecommendation(
        optimalRange: ProteinRecoveryInsight.ProteinRange?,
        currentAverage: Double,
        ranges: [ProteinRecoveryInsight.ProteinRange]
    ) -> String {
        
        guard let optimal = optimalRange else {
            return "Continue tracking to identify your optimal protein intake."
        }
        
        let currentRange = ranges.first { range in
            currentAverage >= range.minProtein && currentAverage < range.maxProtein
        }
        
        if let current = currentRange, current.range == optimal.range {
            return "Your current protein intake (\(Int(currentAverage))g) is in the optimal range for recovery. Next-day HRV averages \(String(format: "%.1f", optimal.avgHRV ?? 0))ms in this range."
        } else {
            let _ = currentAverage < optimal.minProtein ? "increase" : "decrease"
            let target = "\(Int(optimal.minProtein))-\(Int(optimal.maxProtein))g"
            
            if let optimalHRV = optimal.avgHRV, let currentHRV = currentRange?.avgHRV {
                let hrvDiff = optimalHRV - currentHRV
                return "Consider targeting \(target) protein daily. Recovery metrics are \(String(format: "%.1f", abs(hrvDiff)))ms HRV \(hrvDiff > 0 ? "better" : "worse") in that range."
            } else {
                return "Your optimal recovery occurs with \(target) protein daily. Current average: \(Int(currentAverage))g."
            }
        }
    }
    
    // MARK: - Carb Timing & Performance Analysis
    
    struct CarbPerformanceInsight {
        let analysisType: AnalysisType
        let lowCarbPerformance: Double // Now represents WATTS
        let highCarbPerformance: Double // Now represents WATTS
        let percentDifference: Double
        let carbThreshold: Double
        let sampleSize: Int
        let confidence: ConfidenceLevel
        let recommendation: String
        
        enum AnalysisType {
            case preworkout    // Previous day's total carbs
            case postworkout   // Same day refueling
            case dailyTotal    // Overall daily carbs
        }
        
        enum ConfidenceLevel {
            case high, medium, low, insufficient
            
            var description: String {
                switch self {
                case .high: return "High confidence"
                case .medium: return "Medium confidence"
                case .low: return "Low confidence"
                case .insufficient: return "More data needed"
                }
            }
        }
    }
    
    /// Analyzes correlation between carb intake and CYCLING POWER
    func analyzeCarbsVsPerformance(
        nutritionData: [DailyNutrition],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> [CarbPerformanceInsight] {
        
        var insights: [CarbPerformanceInsight] = []
        
        // Analysis 1: Previous day carbs vs Cycling Power
        if let preDayInsight = analyzePreDayCarbs(
            nutritionData: nutritionData,
            healthKitWorkouts: healthKitWorkouts,
            stravaActivities: stravaActivities
        ) {
            insights.append(preDayInsight)
        }
        
        // Analysis 2: Same-day carbs vs Cycling Power
        if let dailyInsight = analyzeDailyCarbs(
            nutritionData: nutritionData,
            healthKitWorkouts: healthKitWorkouts,
            stravaActivities: stravaActivities
        ) {
            insights.append(dailyInsight)
        }
        
        return insights
    }
    
    // MARK: - Helper Methods for Carb Analysis
    
    private func analyzePreDayCarbs(
        nutritionData: [DailyNutrition],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> CarbPerformanceInsight? {
        
        let calendar = Calendar.current
        
        // Create nutrition lookup
        var nutritionByDate: [Date: DailyNutrition] = [:]
        for nutrition in nutritionData where nutrition.isComplete {
            let day = calendar.startOfDay(for: nutrition.date)
            nutritionByDate[day] = nutrition
        }
        
        // Analyze workouts with previous day's carbs
        var lowCarbWorkouts: [Double] = []
        var highCarbWorkouts: [Double] = []
        
        // Use median carb intake as threshold
        let allCarbs = nutritionData.filter { $0.isComplete }.map { $0.totalCarbs }.sorted()
        let carbThreshold: Double
        if allCarbs.isEmpty {
            carbThreshold = 250
        } else {
            let midIndex = allCarbs.count / 2
            carbThreshold = allCarbs[midIndex]
        }
        
        // Process Strava activities (Strictly Cycling with Power)
        for activity in stravaActivities {
            guard let workoutDate = activity.startDateFormatted else { continue }
            
            // STRICT FILTER: Only Rides with Power
            guard activity.type == "Ride" || activity.type == "VirtualRide",
                  let watts = activity.averageWatts, watts > 0 else { continue }
            
            // Get previous day's nutrition
            let workoutDay = calendar.startOfDay(for: workoutDate)
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: workoutDay),
                  let prevDayNutrition = nutritionByDate[previousDay] else {
                continue
            }
            
            // Categorize by previous day's carbs
            if prevDayNutrition.totalCarbs < carbThreshold {
                lowCarbWorkouts.append(watts)
            } else {
                highCarbWorkouts.append(watts)
            }
        }
        
        // Process HealthKit workouts (Strictly Cycling with Power)
        for workout in healthKitWorkouts {
            guard workout.workoutType == .cycling,
                  let watts = workout.averagePower, watts > 0 else { continue }
            
            let workoutDay = calendar.startOfDay(for: workout.startDate)
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: workoutDay),
                  let prevDayNutrition = nutritionByDate[previousDay] else {
                continue
            }
            
            if prevDayNutrition.totalCarbs < carbThreshold {
                lowCarbWorkouts.append(watts)
            } else {
                highCarbWorkouts.append(watts)
            }
        }
        
        // Need at least 3 workouts in each category
        guard lowCarbWorkouts.count >= 3, highCarbWorkouts.count >= 3 else {
            return nil
        }
        
        let avgLow = lowCarbWorkouts.reduce(0, +) / Double(lowCarbWorkouts.count)
        let avgHigh = highCarbWorkouts.reduce(0, +) / Double(highCarbWorkouts.count)
        
        let baseline = max(avgLow, avgHigh)
        let percentDiff = baseline > 0 ? ((avgHigh - avgLow) / baseline) * 100 : 0
        
        let totalSamples = lowCarbWorkouts.count + highCarbWorkouts.count
        let confidence: CarbPerformanceInsight.ConfidenceLevel
        if totalSamples >= 15 {
            confidence = .high
        } else if totalSamples >= 10 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        let recommendation: String
        if abs(percentDiff) < 3.0 {
            recommendation = "Carb intake doesn't significantly impact your cycling power. Focus on timing rather than total quantity."
        } else if percentDiff > 0 {
            recommendation = "You push \(String(format: "%.0f", avgHigh - avgLow))W more power after high-carb days (\(Int(carbThreshold))g+). Fuel up before big rides!"
        } else {
            recommendation = "Interestingly, power is slightly higher after lower-carb days. This might indicate efficient fat adaptation or recovery rides falling on high-carb days."
        }
        
        return CarbPerformanceInsight(
            analysisType: .preworkout,
            lowCarbPerformance: avgLow,
            highCarbPerformance: avgHigh,
            percentDifference: percentDiff,
            carbThreshold: carbThreshold,
            sampleSize: totalSamples,
            confidence: confidence,
            recommendation: recommendation
        )
    }
    
    private func analyzeDailyCarbs(
        nutritionData: [DailyNutrition],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> CarbPerformanceInsight? {
        
        let calendar = Calendar.current
        
        // Create nutrition lookup
        var nutritionByDate: [Date: DailyNutrition] = [:]
        for nutrition in nutritionData where nutrition.isComplete {
            let day = calendar.startOfDay(for: nutrition.date)
            nutritionByDate[day] = nutrition
        }
        
        // Analyze workouts with same-day carbs
        var lowCarbWorkouts: [Double] = []
        var highCarbWorkouts: [Double] = []
        
        let allCarbs = nutritionData.filter { $0.isComplete }.map { $0.totalCarbs }.sorted()
        let carbThreshold: Double
        if allCarbs.isEmpty {
            carbThreshold = 250
        } else {
            let midIndex = allCarbs.count / 2
            carbThreshold = allCarbs[midIndex]
        }
        
        // Process Strava activities (Strictly Cycling with Power)
        for activity in stravaActivities {
            guard let workoutDate = activity.startDateFormatted else { continue }
            
            // STRICT FILTER: Only Rides with Power
            guard activity.type == "Ride" || activity.type == "VirtualRide",
                  let watts = activity.averageWatts, watts > 0 else { continue }
            
            let workoutDay = calendar.startOfDay(for: workoutDate)
            guard let dayNutrition = nutritionByDate[workoutDay] else { continue }
            
            if dayNutrition.totalCarbs < carbThreshold {
                lowCarbWorkouts.append(watts)
            } else {
                highCarbWorkouts.append(watts)
            }
        }
        
        // Process HealthKit workouts (Strictly Cycling with Power)
        for workout in healthKitWorkouts {
            guard workout.workoutType == .cycling,
                  let watts = workout.averagePower, watts > 0 else { continue }
            
            let workoutDay = calendar.startOfDay(for: workout.startDate)
            guard let dayNutrition = nutritionByDate[workoutDay] else { continue }
            
            if dayNutrition.totalCarbs < carbThreshold {
                lowCarbWorkouts.append(watts)
            } else {
                highCarbWorkouts.append(watts)
            }
        }
        
        // Need at least 3 workouts in each category
        guard lowCarbWorkouts.count >= 3, highCarbWorkouts.count >= 3 else {
            return nil
        }
        
        let avgLow = lowCarbWorkouts.reduce(0, +) / Double(lowCarbWorkouts.count)
        let avgHigh = highCarbWorkouts.reduce(0, +) / Double(highCarbWorkouts.count)
        
        let baseline = max(avgLow, avgHigh)
        let percentDiff = baseline > 0 ? ((avgHigh - avgLow) / baseline) * 100 : 0
        
        let totalSamples = lowCarbWorkouts.count + highCarbWorkouts.count
        let confidence: CarbPerformanceInsight.ConfidenceLevel
        if totalSamples >= 15 {
            confidence = .high
        } else if totalSamples >= 10 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        let recommendation: String
        if abs(percentDiff) < 3.0 {
            recommendation = "Same-day carbs show minimal correlation with cycling power. Day-of fueling may be less critical than overall training status."
        } else if percentDiff > 0 {
            recommendation = "Cycling power improves \(String(format: "%.1f", percentDiff))% on days with \(Int(carbThreshold))g+ carbs. Ensure adequate fueling on ride days."
        } else {
            recommendation = "Lower-carb days show slightly better power numbers. This may be due to easier rides being scheduled on high-carb (refuel) days."
        }
        
        return CarbPerformanceInsight(
            analysisType: .dailyTotal,
            lowCarbPerformance: avgLow,
            highCarbPerformance: avgHigh,
            percentDifference: percentDiff,
            carbThreshold: carbThreshold,
            sampleSize: totalSamples,
            confidence: confidence,
            recommendation: recommendation
        )
    }
    
    struct ProteinPerformanceInsight {
        let activityType: String
        let highProteinAvg: Double // Performance metric at high protein
        let lowProteinAvg: Double  // Performance metric at low protein
        let percentDifference: Double
        let proteinThreshold: Double
        let sampleSize: Int
        let recommendation: String
    }

    func analyzeProteinVsPerformance(
        nutritionData: [DailyNutrition],
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> [ProteinPerformanceInsight] {
        let calendar = Calendar.current
        var insights: [ProteinPerformanceInsight] = []
        
        // 1. Create nutrition lookup
        var nutritionByDate: [Date: DailyNutrition] = [:]
        for nutrition in nutritionData where nutrition.isComplete {
            nutritionByDate[calendar.startOfDay(for: nutrition.date)] = nutrition
        }
        
        // 2. Define Threshold
        let threshold: Double = 120.0
        
        // 3. Group workouts by activity type
        var perfByType: [String: (high: [Double], low: [Double])] = [:]
        
        // Combined Strava and HK logic
        // For protein, we might still want to look at Running (Speed) AND Cycling (Watts)
        // But since you asked to focus on power, let's prioritize Watts if available.
        
        let allWorkouts = stravaActivities.compactMap { activity -> (String, Date, Double)? in
            guard let date = activity.startDateFormatted else { return nil }
            // Only use sessions with Power or Speed
            if let watts = activity.averageWatts {
                return (activity.type, date, watts)
            } else if let speed = activity.averageSpeed, activity.type == "Run" {
                return (activity.type, date, speed * 2.23694)
            }
            return nil
        }
        
        for (type, date, perf) in allWorkouts {
            let workoutDay = calendar.startOfDay(for: date)
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: workoutDay),
                  let nutrition = nutritionByDate[prevDay] else { continue }
            
            if perfByType[type] == nil { perfByType[type] = ([], []) }
            
            if nutrition.totalProtein >= threshold {
                perfByType[type]?.high.append(perf)
            } else {
                perfByType[type]?.low.append(perf)
            }
        }
        
        // 4. Calculate Averages
        for (type, data) in perfByType {
            guard data.high.count >= 3, data.low.count >= 3 else { continue }
            
            let avgHigh = data.high.reduce(0, +) / Double(data.high.count)
            let avgLow = data.low.count == 0 ? 0 : data.low.reduce(0, +) / Double(data.low.count)
            let diff = avgLow > 0 ? ((avgHigh - avgLow) / avgLow) * 100 : 0
            
            let metricName = type == "Ride" ? "Power" : "Speed"
            
            let rec = "\(metricName) is \(String(format: "%.1f", abs(diff)))% \(diff > 0 ? "higher" : "lower") on \(type)s after eating \(Int(threshold))g+ of protein."
            
            insights.append(ProteinPerformanceInsight(
                activityType: type,
                highProteinAvg: avgHigh,
                lowProteinAvg: avgLow,
                percentDifference: diff,
                proteinThreshold: threshold,
                sampleSize: data.high.count + data.low.count,
                recommendation: rec
            ))
        }
        
        return insights
    }
}
