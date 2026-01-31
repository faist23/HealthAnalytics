//
//  PerformancePatternAnalyzer.swift
//  HealthAnalytics
//
//  Discovers YOUR unique performance patterns
//  "Best cycling happens 2-3 days after strength training"
//

import Foundation
import HealthKit

struct PerformancePatternAnalyzer {
    
    // MARK: - Pattern Models
    
    /// Discovered performance window based on actual data
    struct PerformanceWindow {
        let activityType: String          // "Run", "Ride", etc.
        let performanceMetric: String     // "Power", "Pace", "Speed"
        let trigger: Trigger              // What needs to happen first
        let optimalWindow: ClosedRange<Int> // Days after trigger
        let averageBoost: Double          // % improvement
        let confidence: Confidence
        let sampleSize: Int
        let lastSeen: Date               // When did this last happen
        
        struct Trigger {
            let type: TriggerType
            let description: String
            
            enum TriggerType {
                case restDay
                case strengthTraining
                case longRun
                case highIntensity
                case nutritionThreshold(macro: String, threshold: Double)
                case sleepQuality(hours: Double)
                case recoveryMetric(metric: String, direction: String)
            }
        }
        
        enum Confidence {
            case strong      // 10+ examples, clear pattern
            case moderate    // 5-9 examples
            case emerging    // 3-4 examples, needs validation
            
            var description: String {
                switch self {
                case .strong: return "Strong pattern"
                case .moderate: return "Moderate confidence"
                case .emerging: return "Emerging pattern"
                }
            }
        }
        
        var readableDescription: String {
            let days = optimalWindow.lowerBound == optimalWindow.upperBound
                ? "\(optimalWindow.lowerBound) day"
                : "\(optimalWindow.lowerBound)-\(optimalWindow.upperBound) days"
            
            // Format the metric name more clearly
            let metricDisplay: String
            if performanceMetric == "Performance" {
                if activityType.contains("Run") {
                    metricDisplay = "running pace"
                } else if activityType.contains("Ride") || activityType.contains("Cycl") {
                    metricDisplay = "cycling power"
                } else {
                    metricDisplay = "performance"
                }
            } else {
                metricDisplay = performanceMetric.lowercased()
            }
            
            // Cap percentage at reasonable value for display
            let cappedBoost = min(abs(averageBoost), 50)
            let boost = String(format: "%.0f", cappedBoost)
            let direction = averageBoost > 0 ? "improves" : "decreases"
            
            return "Your \(metricDisplay) \(direction) by \(boost)% when done \(days) after \(trigger.description)"
        }
    }
    
    /// Timing-based insights
    struct OptimalTiming {
        let activityType: String
        let bestTimeOfDay: TimeRange?
        let bestDayOfWeek: DayOfWeek?
        let performanceDifference: Double // % better
        let sampleSize: Int
        
        enum TimeRange {
            case morning    // 5am-11am
            case midday     // 11am-3pm
            case afternoon  // 3pm-7pm
            case evening    // 7pm-10pm
            
            var description: String {
                switch self {
                case .morning: return "Morning (5-11am)"
                case .midday: return "Midday (11am-3pm)"
                case .afternoon: return "Afternoon (3-7pm)"
                case .evening: return "Evening (7-10pm)"
                }
            }
        }
        
        enum DayOfWeek {
            case monday, tuesday, wednesday, thursday, friday, saturday, sunday
            
            var name: String {
                switch self {
                case .monday: return "Monday"
                case .tuesday: return "Tuesday"
                case .wednesday: return "Wednesday"
                case .thursday: return "Thursday"
                case .friday: return "Friday"
                case .saturday: return "Saturday"
                case .sunday: return "Sunday"
                }
            }
        }
        
        var description: String {
            var parts: [String] = []
            
            if let time = bestTimeOfDay {
                parts.append("\(time.description)")
            }
            
            if let day = bestDayOfWeek {
                parts.append("\(day.name)s")
            }
            
            let timing = parts.isEmpty ? "consistently" : parts.joined(separator: " on ")
            let diff = String(format: "%.0f", abs(performanceDifference))
            
            return "You perform \(diff)% better in \(activityType) during \(timing)"
        }
    }
    
    /// Sequential workout effects
    struct WorkoutSequence {
        let sequence: [String]            // ["Strength", "Rest", "Run"]
        let resultingPerformance: Double  // Performance metric
        let comparisonToBaseline: Double  // % difference from average
        let sampleSize: Int
        
        var description: String {
            let seq = sequence.joined(separator: " → ")
            let diff = String(format: "%.0f", abs(comparisonToBaseline))
            let direction = comparisonToBaseline > 0 ? "better" : "worse"
            
            return "\(seq) sequence yields \(diff)% \(direction) performance"
        }
    }
    
    // MARK: - Analysis Functions
    
    /// Find all performance windows for an athlete
    func discoverPerformanceWindows(
        workouts: [WorkoutData],
        activities: [StravaActivity],
        sleep: [HealthDataPoint],
        nutrition: [DailyNutrition]
    ) -> [PerformanceWindow] {
        
        print("🔍 Discovering Performance Patterns...")
        
        var windows: [PerformanceWindow] = []
        
        // Combine all activities
        let allActivities = combineActivities(workouts: workouts, activities: activities)
        
        // 1. Find post-rest-day performance boosts
        if let restDayPattern = analyzeRestDayEffect(activities: allActivities) {
            windows.append(restDayPattern)
        }
        
        // 2. Find strength training -> endurance performance pattern
        if let strengthPattern = analyzeStrengthToEnduranceEffect(activities: allActivities) {
            windows.append(strengthPattern)
        }
        
        // 3. Find sleep quality -> performance patterns
        let sleepPatterns = analyzeSleepPerformanceWindows(
            activities: allActivities,
            sleep: sleep
        )
        windows.append(contentsOf: sleepPatterns)
        
        // 4. Find nutrition -> performance patterns
        let nutritionPatterns = analyzeNutritionPerformanceWindows(
            activities: allActivities,
            nutrition: nutrition
        )
        windows.append(contentsOf: nutritionPatterns)
        
        print("   ✅ Found \(windows.count) performance windows")
        
        return windows.sorted { $0.confidence.rawValue > $1.confidence.rawValue }
    }
    
    /// Discover optimal timing patterns
    func discoverOptimalTiming(
        workouts: [WorkoutData],
        activities: [StravaActivity]
    ) -> [OptimalTiming] {
        
        print("⏰ Analyzing Optimal Timing...")
        
        var timings: [OptimalTiming] = []
        let allActivities = combineActivities(workouts: workouts, activities: activities)
        
        // Group by activity type
        let byType = Dictionary(grouping: allActivities) { $0.activityType }
        
        for (type, activities) in byType {
            guard activities.count >= 5 else { continue }
            
            // Analyze time of day
            if let timePattern = analyzeTimeOfDay(activities: activities, type: type) {
                timings.append(timePattern)
            }
            
            // Analyze day of week
            if let dayPattern = analyzeDayOfWeek(activities: activities, type: type) {
                timings.append(dayPattern)
            }
        }
        
        print("   ✅ Found \(timings.count) timing patterns")
        
        return timings
    }
    
    /// Discover effective workout sequences
    func discoverWorkoutSequences(
        workouts: [WorkoutData],
        activities: [StravaActivity]
    ) -> [WorkoutSequence] {
        
        print("🔄 Analyzing Workout Sequences...")
        
        var sequences: [WorkoutSequence] = []
        let allActivities = combineActivities(workouts: workouts, activities: activities)
            .sorted { $0.startDate < $1.startDate }
        
        // Look for 3-day sequences
        for i in 0..<(allActivities.count - 2) {
            let day1 = allActivities[i]
            let day2Index = findNextDayActivity(after: i, in: allActivities)
            guard let day2Idx = day2Index else { continue }
            
            let day3Index = findNextDayActivity(after: day2Idx, in: allActivities)
            guard let day3Idx = day3Index else { continue }
            
            let day2 = allActivities[day2Idx]
            let day3 = allActivities[day3Idx]
            
            // Check if day3 has performance data
            guard let performance = extractPerformance(from: day3) else { continue }
            
            let sequence = [day1.activityType, day2.activityType, day3.activityType]
            
            // Compare to baseline for day3 type
            let baseline = calculateBaseline(
                for: day3.activityType,
                in: allActivities
            )
            
            let difference = ((performance - baseline) / baseline) * 100
            
            // Only keep significant patterns (>5% difference)
            if abs(difference) > 5 {
                sequences.append(WorkoutSequence(
                    sequence: sequence,
                    resultingPerformance: performance,
                    comparisonToBaseline: difference,
                    sampleSize: 1 // Would need more sophisticated grouping
                ))
            }
        }
        
        print("   ✅ Found \(sequences.count) sequence patterns")
        
        return sequences.sorted { abs($0.comparisonToBaseline) > abs($1.comparisonToBaseline) }
    }
    
    // MARK: - Pattern Analysis Helpers
    
    private func analyzeRestDayEffect(
        activities: [EnrichedActivity]
    ) -> PerformanceWindow? {
        
        guard activities.count >= 10 else { return nil }
        
        var performancesAfter0Days: [Double] = []
        var performancesAfter1Day: [Double] = []
        var performancesAfter2Days: [Double] = []
        var performancesAfter3Days: [Double] = []
        
        for i in 0..<activities.count {
            let activity = activities[i]
            guard let performance = extractPerformance(from: activity) else { continue }
            
            // Look back to find last workout
            let daysSinceLastWorkout = findDaysSinceLastWorkout(
                before: i,
                in: activities
            )
            
            switch daysSinceLastWorkout {
            case 0:
                performancesAfter0Days.append(performance)
            case 1:
                performancesAfter1Day.append(performance)
            case 2:
                performancesAfter2Days.append(performance)
            case 3:
                performancesAfter3Days.append(performance)
            default:
                break
            }
        }
        
        // Find the best window
        let windows = [
            (0...0, performancesAfter0Days),
            (1...1, performancesAfter1Day),
            (2...2, performancesAfter2Days),
            (3...3, performancesAfter3Days)
        ]
        
        guard let best = windows.max(by: {
            ($0.1.isEmpty ? 0 : $0.1.reduce(0, +) / Double($0.1.count)) <
            ($1.1.isEmpty ? 0 : $1.1.reduce(0, +) / Double($1.1.count))
        }), !best.1.isEmpty, best.1.count >= 3 else {
            return nil
        }
        
        let baseline = performancesAfter0Days.isEmpty ?
            best.1.reduce(0, +) / Double(best.1.count) :
            performancesAfter0Days.reduce(0, +) / Double(performancesAfter0Days.count)
        
        let bestAvg = best.1.reduce(0, +) / Double(best.1.count)
        let boost = ((bestAvg - baseline) / baseline) * 100
        
        // Validate: must be at least 5% difference and less than 50% (sanity check)
        guard abs(boost) > 5, abs(boost) < 50 else {
            return nil
        }
        
        return PerformanceWindow(
            activityType: "All activities",
            performanceMetric: "Performance",
            trigger: PerformanceWindow.Trigger(
                type: .restDay,
                description: "rest day"
            ),
            optimalWindow: best.0,
            averageBoost: boost,
            confidence: best.1.count >= 10 ? .strong : (best.1.count >= 5 ? .moderate : .emerging),
            sampleSize: best.1.count,
            lastSeen: activities.last?.startDate ?? Date()
        )
    }
    
    private func analyzeStrengthToEnduranceEffect(
        activities: [EnrichedActivity]
    ) -> PerformanceWindow? {
        
        var performancesByDay: [Int: [Double]] = [:]
        
        for i in 0..<activities.count {
            let activity = activities[i]
            
            // Only look at endurance activities
            guard ["Run", "Ride", "Swim"].contains(activity.activityType) else {
                continue
            }
            
            guard let performance = extractPerformance(from: activity) else {
                continue
            }
            
            // Look back for strength training
            let daysSinceStrength = findDaysSinceActivityType(
                "Strength",
                before: i,
                in: activities,
                maxDays: 5
            )
            
            if let days = daysSinceStrength {
                performancesByDay[days, default: []].append(performance)
            }
        }
        
        // Find optimal window
        guard let bestDay = performancesByDay.max(by: {
            let avg1 = $0.value.reduce(0, +) / Double($0.value.count)
            let avg2 = $1.value.reduce(0, +) / Double($1.value.count)
            return avg1 < avg2
        }) else {
            return nil
        }
        
        guard bestDay.value.count >= 3 else { return nil }
        
        let bestAvg = bestDay.value.reduce(0, +) / Double(bestDay.value.count)
        
        // Calculate baseline (all performances)
        let allPerformances = performancesByDay.values.flatMap { $0 }
        let baseline = allPerformances.reduce(0, +) / Double(allPerformances.count)
        
        let boost = ((bestAvg - baseline) / baseline) * 100
        
        guard abs(boost) > 5 else { return nil }
        
        return PerformanceWindow(
            activityType: "Endurance",
            performanceMetric: "Performance",
            trigger: PerformanceWindow.Trigger(
                type: .strengthTraining,
                description: "strength training"
            ),
            optimalWindow: bestDay.key...bestDay.key,
            averageBoost: boost,
            confidence: bestDay.value.count >= 10 ? .strong : (bestDay.value.count >= 5 ? .moderate : .emerging),
            sampleSize: bestDay.value.count,
            lastSeen: activities.last?.startDate ?? Date()
        )
    }
    
    private func analyzeSleepPerformanceWindows(
        activities: [EnrichedActivity],
        sleep: [HealthDataPoint]
    ) -> [PerformanceWindow] {
        
        var windows: [PerformanceWindow] = []
        
        // Group by activity type
        let byType = Dictionary(grouping: activities) { $0.activityType }
        
        for (type, typeActivities) in byType {
            guard typeActivities.count >= 5 else { continue }
            
            var goodSleepPerformances: [Double] = []
            var poorSleepPerformances: [Double] = []
            
            for activity in typeActivities {
                guard let performance = extractPerformance(from: activity) else {
                    continue
                }
                
                // Find sleep from previous night
                let activityDate = Calendar.current.startOfDay(for: activity.startDate)
                if let sleepData = sleep.first(where: {
                    Calendar.current.isDate($0.date, inSameDayAs: activityDate)
                }) {
                    if sleepData.value >= 7.0 {
                        goodSleepPerformances.append(performance)
                    } else {
                        poorSleepPerformances.append(performance)
                    }
                }
            }
            
            guard goodSleepPerformances.count >= 3,
                  poorSleepPerformances.count >= 3 else {
                continue
            }
            
            let goodAvg = goodSleepPerformances.reduce(0, +) / Double(goodSleepPerformances.count)
            let poorAvg = poorSleepPerformances.reduce(0, +) / Double(poorSleepPerformances.count)
            
            let boost = ((goodAvg - poorAvg) / poorAvg) * 100
            
            guard abs(boost) > 5 else { continue }
            
            windows.append(PerformanceWindow(
                activityType: type,
                performanceMetric: "Performance",
                trigger: PerformanceWindow.Trigger(
                    type: .sleepQuality(hours: 7.0),
                    description: "7+ hours sleep"
                ),
                optimalWindow: 0...0, // Same day
                averageBoost: boost,
                confidence: goodSleepPerformances.count >= 10 ? .strong : .moderate,
                sampleSize: goodSleepPerformances.count,
                lastSeen: activities.last?.startDate ?? Date()
            ))
        }
        
        return windows
    }
    
    private func analyzeNutritionPerformanceWindows(
        activities: [EnrichedActivity],
        nutrition: [DailyNutrition]
    ) -> [PerformanceWindow] {
        
        var windows: [PerformanceWindow] = []
        
        // Analyze carb intake day before
        let byType = Dictionary(grouping: activities) { $0.activityType }
        
        for (type, typeActivities) in byType {
            guard typeActivities.count >= 8 else { continue }
            
            var highCarbPerformances: [Double] = []
            var lowCarbPerformances: [Double] = []
            
            for activity in typeActivities {
                guard let performance = extractPerformance(from: activity) else {
                    continue
                }
                
                // Find nutrition from previous day
                let previousDay = Calendar.current.date(
                    byAdding: .day,
                    value: -1,
                    to: Calendar.current.startOfDay(for: activity.startDate)
                )!
                
                if let nutritionData = nutrition.first(where: {
                    Calendar.current.isDate($0.date, inSameDayAs: previousDay)
                }) {
                    if nutritionData.totalCarbs >= 200 {
                        highCarbPerformances.append(performance)
                    } else if nutritionData.totalCarbs < 150 {
                        lowCarbPerformances.append(performance)
                    }
                }
            }
            
            guard highCarbPerformances.count >= 3,
                  lowCarbPerformances.count >= 3 else {
                continue
            }
            
            let highAvg = highCarbPerformances.reduce(0, +) / Double(highCarbPerformances.count)
            let lowAvg = lowCarbPerformances.reduce(0, +) / Double(lowCarbPerformances.count)
            
            let boost = ((highAvg - lowAvg) / lowAvg) * 100
            
            guard abs(boost) > 5 else { continue }
            
            windows.append(PerformanceWindow(
                activityType: type,
                performanceMetric: "Performance",
                trigger: PerformanceWindow.Trigger(
                    type: .nutritionThreshold(macro: "Carbs", threshold: 200),
                    description: "200g+ carbs previous day"
                ),
                optimalWindow: 1...1, // Next day
                averageBoost: boost,
                confidence: highCarbPerformances.count >= 8 ? .strong : .moderate,
                sampleSize: highCarbPerformances.count,
                lastSeen: activities.last?.startDate ?? Date()
            ))
        }
        
        return windows
    }
    
    private func analyzeTimeOfDay(
        activities: [EnrichedActivity],
        type: String
    ) -> OptimalTiming? {
        
        var performanceByTime: [OptimalTiming.TimeRange: [Double]] = [:]
        
        for activity in activities {
            guard let performance = extractPerformance(from: activity) else {
                continue
            }
            
            let hour = Calendar.current.component(.hour, from: activity.startDate)
            let timeRange: OptimalTiming.TimeRange
            
            switch hour {
            case 5..<11:
                timeRange = .morning
            case 11..<15:
                timeRange = .midday
            case 15..<19:
                timeRange = .afternoon
            case 19..<22:
                timeRange = .evening
            default:
                continue
            }
            
            performanceByTime[timeRange, default: []].append(performance)
        }
        
        guard let best = performanceByTime.max(by: {
            let avg1 = $0.value.reduce(0, +) / Double($0.value.count)
            let avg2 = $1.value.reduce(0, +) / Double($1.value.count)
            return avg1 < avg2
        }), best.value.count >= 3 else {
            return nil
        }
        
        let bestAvg = best.value.reduce(0, +) / Double(best.value.count)
        let allPerformances = performanceByTime.values.flatMap { $0 }
        let baseline = allPerformances.reduce(0, +) / Double(allPerformances.count)
        
        let difference = ((bestAvg - baseline) / baseline) * 100
        
        guard abs(difference) > 5 else { return nil }
        
        return OptimalTiming(
            activityType: type,
            bestTimeOfDay: best.key,
            bestDayOfWeek: nil,
            performanceDifference: difference,
            sampleSize: best.value.count
        )
    }
    
    private func analyzeDayOfWeek(
        activities: [EnrichedActivity],
        type: String
    ) -> OptimalTiming? {
        
        // Similar to time of day but for weekday patterns
        // Implementation would be analogous
        return nil
    }
    
    // MARK: - Helper Functions
    
    private struct EnrichedActivity {
        let activityType: String
        let startDate: Date
        let duration: TimeInterval
        let distance: Double?
        let power: Double?
        let pace: Double?
        let speed: Double?
    }
    
    private func combineActivities(
        workouts: [WorkoutData],
        activities: [StravaActivity]
    ) -> [EnrichedActivity] {
        
        var enriched: [EnrichedActivity] = []
        
        for workout in workouts {
            let type = workoutTypeToString(workout.workoutType)
            let pace = (workout.totalDistance != nil && workout.duration > 0) ?
                workout.duration / (workout.totalDistance! / 1609.34) : nil // min/mile
            let speed = workout.totalDistance != nil ?
                workout.totalDistance! / workout.duration : nil
            
            enriched.append(EnrichedActivity(
                activityType: type,
                startDate: workout.startDate,
                duration: workout.duration,
                distance: workout.totalDistance,
                power: workout.averagePower,
                pace: pace,
                speed: speed
            ))
        }
        
        for activity in activities {
            guard let startDate = activity.startDateFormatted else { continue }
            
            let pace = (activity.distance > 0 && activity.movingTime > 0) ?
                Double(activity.movingTime) / (activity.distance / 1609.34) : nil
            let speed = activity.distance / Double(activity.movingTime)
            
            enriched.append(EnrichedActivity(
                activityType: activity.type,
                startDate: startDate,
                duration: TimeInterval(activity.movingTime),
                distance: activity.distance,
                power: activity.averageWatts,
                pace: pace,
                speed: speed
            ))
        }
        
        return enriched.sorted { $0.startDate < $1.startDate }
    }
    
    private func extractPerformance(from activity: EnrichedActivity) -> Double? {
        // Return normalized performance metric
        // For power: use watts directly
        // For speed: use m/s
        // For pace: convert to speed (m/s) so higher is better
        
        if let power = activity.power, power > 0 {
            return power
        }
        
        if let speed = activity.speed, speed > 0 {
            return speed
        }
        
        if let pace = activity.pace, pace > 0, pace < 1000 {
            // Pace is min/mile, convert to speed (higher = better)
            // Speed in m/s = 1609.34 meters per mile / (pace * 60 seconds)
            let speedMetersPerSecond = 1609.34 / (pace * 60.0)
            return speedMetersPerSecond
        }
        
        return nil
    }
    
    private func workoutTypeToString(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            return "Run"
        case .cycling:
            return "Ride"
        case .swimming:
            return "Swim"
        case .walking:
            return "Walk"
        case .hiking:
            return "Hike"
        case .functionalStrengthTraining, .traditionalStrengthTraining:
            return "Strength"
        default:
            return "Other"
        }
    }
    
    private func findDaysSinceLastWorkout(
        before index: Int,
        in activities: [EnrichedActivity]
    ) -> Int {
        
        guard index > 0 else { return 0 }
        
        let current = activities[index]
        let currentDay = Calendar.current.startOfDay(for: current.startDate)
        
        for i in stride(from: index - 1, through: 0, by: -1) {
            let prev = activities[i]
            let prevDay = Calendar.current.startOfDay(for: prev.startDate)
            
            let days = Calendar.current.dateComponents([.day], from: prevDay, to: currentDay).day ?? 0
            
            if days >= 1 {
                return days
            }
        }
        
        return 0
    }
    
    private func findDaysSinceActivityType(
        _ type: String,
        before index: Int,
        in activities: [EnrichedActivity],
        maxDays: Int
    ) -> Int? {
        
        guard index > 0 else { return nil }
        
        let current = activities[index]
        let currentDay = Calendar.current.startOfDay(for: current.startDate)
        
        for i in stride(from: index - 1, through: 0, by: -1) {
            let prev = activities[i]
            
            if prev.activityType == type {
                let prevDay = Calendar.current.startOfDay(for: prev.startDate)
                let days = Calendar.current.dateComponents([.day], from: prevDay, to: currentDay).day ?? 0
                
                if days <= maxDays {
                    return days
                }
            }
        }
        
        return nil
    }
    
    private func findNextDayActivity(
        after index: Int,
        in activities: [EnrichedActivity]
    ) -> Int? {
        
        guard index < activities.count - 1 else { return nil }
        
        let current = activities[index]
        let currentDay = Calendar.current.startOfDay(for: current.startDate)
        
        for i in (index + 1)..<activities.count {
            let next = activities[i]
            let nextDay = Calendar.current.startOfDay(for: next.startDate)
            
            let days = Calendar.current.dateComponents([.day], from: currentDay, to: nextDay).day ?? 0
            
            if days >= 1 {
                return i
            }
        }
        
        return nil
    }
    
    private func calculateBaseline(
        for type: String,
        in activities: [EnrichedActivity]
    ) -> Double {
        
        let typeActivities = activities.filter { $0.activityType == type }
        let performances = typeActivities.compactMap { extractPerformance(from: $0) }
        
        guard !performances.isEmpty else { return 0 }
        
        return performances.reduce(0, +) / Double(performances.count)
    }
}

// Make Confidence comparable for sorting
extension PerformancePatternAnalyzer.PerformanceWindow.Confidence: Comparable {
    var rawValue: Int {
        switch self {
        case .strong: return 3
        case .moderate: return 2
        case .emerging: return 1
        }
    }
    
    static func < (lhs: PerformancePatternAnalyzer.PerformanceWindow.Confidence, rhs: PerformancePatternAnalyzer.PerformanceWindow.Confidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
