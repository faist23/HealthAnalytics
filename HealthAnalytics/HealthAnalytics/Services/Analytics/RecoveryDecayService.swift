//
//  RecoveryDecayService.swift
//  HealthAnalytics
//
//  Models the intra-day "decay" of readiness after a workout and the subsequent 
//  recovery curve over time.
//

import Foundation
import HealthKit

class RecoveryDecayService {
    
    struct IntraDayReadiness {
        let currentScore: Int
        let baselineScore: Int
        let fatigueImpact: Int
        let recoveryPercentage: Double // 0-1
        let timeToFullRecovery: TimeInterval // Seconds from now
        let recoveryPoint: Date // When score will be 100% of baseline
        
        var isFullyRecovered: Bool {
            currentScore >= baselineScore
        }
    }
    
    /// Calculates the current dynamic readiness score based on workouts completed TODAY.
    func calculateIntraDayReadiness(baselineScore: Int, todayWorkouts: [WorkoutData], now: Date = Date()) -> IntraDayReadiness {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // 1. Filter workouts completed since midnight
        let completedToday = todayWorkouts.filter { $0.startDate >= today && $0.endDate <= now }
        
        guard !completedToday.isEmpty else {
            return IntraDayReadiness(
                currentScore: baselineScore,
                baselineScore: baselineScore,
                fatigueImpact: 0,
                recoveryPercentage: 1.0,
                timeToFullRecovery: 0,
                recoveryPoint: now
            )
        }
        
        // 2. Calculate "Fatigue Debt" for each workout
        // Each workout creates a debt that decays over time.
        var totalCurrentFatigue: Double = 0
        var latestRecoveryPoint = now
        
        for workout in completedToday {
            let load = calculateWorkoutFatigueLoad(workout)
            let timeSinceEnd = now.timeIntervalSince(workout.endDate)
            
            // Recovery Model: Exponential decay of fatigue
            // Half-life of fatigue depends on intensity. 
            // Average half-life: 6 hours (21600 seconds) for moderate work.
            let halfLife: Double = determineHalfLife(for: workout)
            let decayConstant = log(2.0) / halfLife
            
            let remainingFatigue = load * exp(-decayConstant * max(0, timeSinceEnd))
            totalCurrentFatigue += remainingFatigue
            
            // Calculate when THIS workout's fatigue will be < 1%
            let recoveryTime = -log(0.01 / load) / decayConstant
            let workoutRecoveryPoint = workout.endDate.addingTimeInterval(recoveryTime)
            if workoutRecoveryPoint > latestRecoveryPoint {
                latestRecoveryPoint = workoutRecoveryPoint
            }
        }
        
        // 3. Map fatigue to score points (0-40 point swing)
        let fatigueImpact = Int(min(totalCurrentFatigue, 50.0)) // Cap impact
        let currentScore = max(0, baselineScore - fatigueImpact)
        
        return IntraDayReadiness(
            currentScore: currentScore,
            baselineScore: baselineScore,
            fatigueImpact: fatigueImpact,
            recoveryPercentage: 1.0 - (Double(fatigueImpact) / 50.0),
            timeToFullRecovery: latestRecoveryPoint.timeIntervalSince(now),
            recoveryPoint: latestRecoveryPoint
        )
    }
    
    // MARK: - Mathematical Models
    
    /// Assigns a "Fatigue Points" value to a workout (0-50 scale)
    private func calculateWorkoutFatigueLoad(_ workout: WorkoutData) -> Double {
        let durationHours = workout.duration / 3600.0
        
        // Base points by activity type
        var basePoints: Double
        switch workout.workoutType {
        case .running: basePoints = 25.0
        case .cycling: basePoints = 20.0
        case .swimming: basePoints = 22.0
        case .functionalStrengthTraining: basePoints = 18.0
        default: basePoints = 15.0
        }
        
        // Intensity scaling (if heart rate is available)
        var intensityMultiplier = 1.0
        if let avgHR = workout.averageHeartRate {
            if avgHR > 160 { intensityMultiplier = 1.5 }
            else if avgHR > 140 { intensityMultiplier = 1.2 }
            else if avgHR < 120 { intensityMultiplier = 0.8 }
        }
        
        return basePoints * durationHours * intensityMultiplier
    }
    
    /// Determines the recovery half-life in seconds based on workout intensity
    private func determineHalfLife(for workout: WorkoutData) -> Double {
        let baseHalfLife: Double = 6 * 3600 // 6 hours
        
        if let hr = workout.averageHeartRate, hr > 160 {
            return 10 * 3600 // Hard sessions take 10 hours half-life
        }
        
        if workout.duration > 2 * 3600 {
            return 8 * 3600 // Long sessions take 8 hours half-life
        }
        
        return baseHalfLife
    }
}
