//
//  IntentAwareReadinessService.swift
//  HealthAnalytics
//
//  Enhanced readiness calculations that use activity intent to provide
//  more accurate, context-aware insights
//

import Foundation
import SwiftData
import HealthKit

struct IntentAwareReadinessService {
    
    // MARK: - Enhanced Readiness Assessment
    
    struct EnhancedReadinessAssessment {
        let acwr: Double
        let chronicLoad: Double
        let acuteLoad: Double
        let trend: Trend
        
        // NEW: Intent-specific insights
        let performanceReadiness: [ActivityIntent: ReadinessLevel]
        let recommendedIntents: [ActivityIntent]
        let shouldAvoidIntents: [ActivityIntent]
        
        enum Trend {
            case building
            case optimal
            case detraining
        }
        
        enum ReadinessLevel {
            case excellent  // Ready for hard efforts
            case good       // Ready for moderate efforts
            case fair       // Easy efforts only
            case poor       // Rest recommended
            
            var emoji: String {
                switch self {
                case .excellent: return "🟢"
                case .good: return "🟡"
                case .fair: return "🟠"
                case .poor: return "🔴"
                }
            }
            
            var priority: Int {
                switch self {
                case .excellent: return 4
                case .good: return 3
                case .fair: return 2
                case .poor: return 1
                }
            }
        }
    }
    
    /// Calculate readiness with intent-aware logic
    func calculateEnhancedReadiness(
        workouts: [StoredWorkout],
        labels: [StoredIntentLabel],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint]
    ) -> EnhancedReadinessAssessment {
        
        // Build lookup for intent labels
        let intentLookup = Dictionary(uniqueKeysWithValues: labels.map { ($0.workoutId, $0.intent) })
        
        // Separate workouts by intent
        let intentWorkouts = Dictionary(grouping: workouts) { workout in
            intentLookup[workout.id] ?? .other
        }
        
        // Calculate ACWR only for performance-oriented workouts
        let performanceIntents: [ActivityIntent] = [.race, .tempo, .intervals, .long]
        let performanceWorkouts = workouts.filter { workout in
            if let intent = intentLookup[workout.id] {
                return performanceIntents.contains(intent)
            }
            return false
        }
        
        let chronicLoad = calculateChronicLoad(workouts: performanceWorkouts)
        let acuteLoad = calculateAcuteLoad(workouts: performanceWorkouts)
        let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
        
        // Determine trend
        let trend: EnhancedReadinessAssessment.Trend
        if acwr > 1.3 {
            trend = .building
        } else if acwr < 0.8 {
            trend = .detraining
        } else {
            trend = .optimal
        }
        
        // Calculate readiness per intent
        let performanceReadiness = calculateIntentReadiness(
            acwr: acwr,
            intentWorkouts: intentWorkouts,
            sleep: sleep,
            hrv: hrv
        )
        
        // Recommend appropriate intents
        let recommended = recommendIntents(readiness: performanceReadiness, acwr: acwr)
        let shouldAvoid = avoidIntents(readiness: performanceReadiness, acwr: acwr)
        
        return EnhancedReadinessAssessment(
            acwr: acwr,
            chronicLoad: chronicLoad,
            acuteLoad: acuteLoad,
            trend: trend,
            performanceReadiness: performanceReadiness,
            recommendedIntents: recommended,
            shouldAvoidIntents: shouldAvoid
        )
    }
    
    // MARK: - Intent-Specific Readiness
    
    private func calculateIntentReadiness(
        acwr: Double,
        intentWorkouts: [ActivityIntent: [StoredWorkout]],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint]
    ) -> [ActivityIntent: EnhancedReadinessAssessment.ReadinessLevel] {
        
        var readiness: [ActivityIntent: EnhancedReadinessAssessment.ReadinessLevel] = [:]
        
        // Get recent recovery metrics
        let recentSleep = sleep.suffix(3)  // Last 3 nights
        let recentHRV = hrv.suffix(7)      // Last 7 days
        
        let avgSleep = recentSleep.isEmpty ? 7.0 : recentSleep.map { $0.value }.reduce(0, +) / Double(recentSleep.count)
        let avgHRV = recentHRV.isEmpty ? 50.0 : recentHRV.map { $0.value }.reduce(0, +) / Double(recentHRV.count)
        
        // Days since last hard effort
        let daysSinceHardEffort = calculateDaysSinceHardEffort(intentWorkouts: intentWorkouts)
        
        // Race/PR Attempts - needs excellent recovery
        if acwr <= 1.2 && avgSleep >= 7.5 && avgHRV >= 50 && daysSinceHardEffort >= 2 {
            readiness[.race] = .excellent
        } else if acwr <= 1.4 && avgSleep >= 7.0 {
            readiness[.race] = .good
        } else if acwr <= 1.5 {
            readiness[.race] = .fair
        } else {
            readiness[.race] = .poor
        }
        
        // Tempo/Threshold - moderate recovery needed
        if acwr <= 1.3 && avgSleep >= 7.0 {
            readiness[.tempo] = .excellent
        } else if acwr <= 1.5 {
            readiness[.tempo] = .good
        } else {
            readiness[.tempo] = .fair
        }
        
        // Intervals - high recovery needed
        if acwr <= 1.2 && avgSleep >= 7.0 && daysSinceHardEffort >= 1 {
            readiness[.intervals] = .excellent
        } else if acwr <= 1.4 && avgSleep >= 6.5 {
            readiness[.intervals] = .good
        } else if acwr <= 1.5 {
            readiness[.intervals] = .fair
        } else {
            readiness[.intervals] = .poor
        }
        
        // Easy runs - almost always okay
        if acwr <= 1.6 {
            readiness[.easy] = .excellent
        } else if acwr <= 1.8 {
            readiness[.easy] = .good
        } else {
            readiness[.easy] = .fair
        }
        
        // Long runs - needs good base
        if acwr >= 0.9 && acwr <= 1.3 && avgSleep >= 7.0 {
            readiness[.long] = .excellent
        } else if acwr >= 0.8 && acwr <= 1.4 {
            readiness[.long] = .good
        } else {
            readiness[.long] = .fair
        }
        
        // Strength - recovery dependent
        if daysSinceHardEffort >= 1 && acwr <= 1.4 {
            readiness[.strength] = .excellent
        } else if acwr <= 1.5 {
            readiness[.strength] = .good
        } else {
            readiness[.strength] = .fair
        }
        
        // Casual walks - always safe
        readiness[.casualWalk] = .excellent
        
        // Other activities - conservative approach
        if acwr <= 1.4 {
            readiness[.other] = .good
        } else {
            readiness[.other] = .fair
        }
        
        return readiness
    }
    
    private func calculateDaysSinceHardEffort(intentWorkouts: [ActivityIntent: [StoredWorkout]]) -> Int {
        let hardIntents: [ActivityIntent] = [.race, .tempo, .intervals]
        
        var mostRecentHard: Date? = nil
        
        for intent in hardIntents {
            if let workouts = intentWorkouts[intent],
               let recent = workouts.max(by: { $0.startDate < $1.startDate }) {
                if mostRecentHard == nil || recent.startDate > mostRecentHard! {
                    mostRecentHard = recent.startDate
                }
            }
        }
        
        guard let lastHard = mostRecentHard else { return 7 }  // Default to well-rested
        
        let days = Calendar.current.dateComponents([.day], from: lastHard, to: Date()).day ?? 0
        return days
    }
    
    private func recommendIntents(
        readiness: [ActivityIntent: EnhancedReadinessAssessment.ReadinessLevel],
        acwr: Double
    ) -> [ActivityIntent] {
        
        var recommended: [ActivityIntent] = []
        
        for (intent, level) in readiness {
            if level == .excellent || level == .good {
                recommended.append(intent)
            }
        }
        
        return recommended.sorted { intent1, intent2 in
            let level1 = readiness[intent1] ?? .poor
            let level2 = readiness[intent2] ?? .poor
            return level1.priority > level2.priority
        }
    }
    
    private func avoidIntents(
        readiness: [ActivityIntent: EnhancedReadinessAssessment.ReadinessLevel],
        acwr: Double
    ) -> [ActivityIntent] {
        
        var avoid: [ActivityIntent] = []
        
        for (intent, level) in readiness {
            if level == .poor {
                avoid.append(intent)
            }
        }
        
        return avoid
    }
    
    // MARK: - Load Calculations
    
    private func calculateChronicLoad(workouts: [StoredWorkout]) -> Double {
        let calendar = Calendar.current
        let now = Date()
        
        guard let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: now) else {
            return 0
        }
        
        let recentWorkouts = workouts.filter { $0.startDate >= twentyEightDaysAgo }
        
        guard !recentWorkouts.isEmpty else { return 0 }
        
        let totalLoad = recentWorkouts.reduce(0.0) { sum, workout in
            sum + calculateWorkoutLoad(workout)
        }
        
        return totalLoad / 28.0
    }
    
    private func calculateAcuteLoad(workouts: [StoredWorkout]) -> Double {
        let calendar = Calendar.current
        let now = Date()
        
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) else {
            return 0
        }
        
        let recentWorkouts = workouts.filter { $0.startDate >= sevenDaysAgo }
        
        guard !recentWorkouts.isEmpty else { return 0 }
        
        let totalLoad = recentWorkouts.reduce(0.0) { sum, workout in
            sum + calculateWorkoutLoad(workout)
        }
        
        return totalLoad / 7.0
    }
    
    private func calculateWorkoutLoad(_ workout: StoredWorkout) -> Double {
        let durationHours = workout.duration / 3600.0
        let multiplier = sportMultiplier(for: workout.workoutType)
        return durationHours * multiplier
    }
    
    private func sportMultiplier(for type: HKWorkoutActivityType) -> Double {
        switch type {
        case .running: return 1.2
        case .cycling: return 1.0
        case .swimming: return 1.3
        case .functionalStrengthTraining, .traditionalStrengthTraining: return 1.1
        case .walking: return 0.5
        default: return 1.0
        }
    }
}
