//
//  RecoveryDecayService.swift
//  HealthAnalytics
//
//  Models the intra-day "decay" of readiness after a workout and the subsequent
//  recovery curve over time, including carry-forward fatigue from prior days.
//

import Foundation
import HealthKit

class RecoveryDecayService {

    struct IntraDayReadiness {
        let currentScore: Int
        let baselineScore: Int
        /// Target score at full recovery (baseline + carried-forward fatigue being repaid).
        /// On a day with no prior-day debt, ceilingScore == baselineScore.
        let ceilingScore: Int
        let fatigueImpact: Int
        let recoveryPercentage: Double // 0-1
        let timeToFullRecovery: TimeInterval // Seconds from now
        let recoveryPoint: Date // When score will be 100% of ceiling

        var isFullyRecovered: Bool {
            currentScore >= ceilingScore
        }
    }

    /// Calculates the current dynamic readiness score based on workouts completed TODAY
    /// and any carry-forward fatigue from prior days.
    ///
    /// - Parameters:
    ///   - baselineScore: This morning's readiness score (already reflects prior-day strain).
    ///   - todayWorkouts: All known workouts; filtered internally to today only.
    ///   - priorDayFatigueImpact: Estimated fatigue points still owed from prior days.
    ///     Pass `Double(30 - breakdown.fatigueScore)` from the ScoreBreakdown. Defaults to 0.
    ///   - now: Defaults to the real current time; override for simulation.
    func calculateIntraDayReadiness(
        baselineScore: Int,
        todayWorkouts: [WorkoutData],
        priorDayFatigueImpact: Double = 0,
        now: Date = Date()
    ) -> IntraDayReadiness {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        // Ceiling: what the score would be if all fatigue (prior + today) were fully resolved.
        let ceilingScore = min(100, baselineScore + Int(round(priorDayFatigueImpact)))

        // Prior-day carry-forward decays with a 16-hour half-life (slower than same-day fatigue).
        // At 7 hours (mid-day after morning HRV read) ~26% has decayed; at 16h ~50%.
        let priorHalfLife: Double = 16 * 3600
        let priorDecay = log(2.0) / priorHalfLife
        let elapsedSinceMidnight = max(0, now.timeIntervalSince(startOfDay))
        let priorDayRemaining = priorDayFatigueImpact * exp(-priorDecay * elapsedSinceMidnight)

        // Filter workouts completed since midnight up to `now`.
        let completedToday = todayWorkouts.filter { $0.startDate >= startOfDay && $0.endDate <= now }

        // Fast path: no today workouts and negligible carry-forward.
        guard !completedToday.isEmpty || priorDayRemaining > 0.5 else {
            return IntraDayReadiness(
                currentScore: baselineScore,
                baselineScore: baselineScore,
                ceilingScore: ceilingScore,
                fatigueImpact: 0,
                recoveryPercentage: 1.0,
                timeToFullRecovery: 0,
                recoveryPoint: now
            )
        }

        // Accumulate today's workout fatigue.
        var totalCurrentFatigue: Double = priorDayRemaining
        var latestRecoveryPoint = now

        for workout in completedToday {
            let load = calculateWorkoutFatigueLoad(workout)
            let timeSinceEnd = now.timeIntervalSince(workout.endDate)
            let halfLife = determineHalfLife(for: workout)
            let decayConstant = log(2.0) / halfLife

            totalCurrentFatigue += load * exp(-decayConstant * max(0, timeSinceEnd))

            // When will this workout's fatigue drop below 1%?
            let recoveryTime = -log(0.01 / load) / decayConstant
            let workoutRecoveryPoint = workout.endDate.addingTimeInterval(recoveryTime)
            if workoutRecoveryPoint > latestRecoveryPoint {
                latestRecoveryPoint = workoutRecoveryPoint
            }
        }

        // When will carry-forward prior-day fatigue drop below 1%?
        if priorDayFatigueImpact > 0 {
            let priorFullRecoveryTime = -log(0.01 / priorDayFatigueImpact) / priorDecay
            let priorRecoveryPoint = startOfDay.addingTimeInterval(priorFullRecoveryTime)
            if priorRecoveryPoint > latestRecoveryPoint {
                latestRecoveryPoint = priorRecoveryPoint
            }
        }

        let fatigueImpact = Int(min(totalCurrentFatigue, 50.0))
        let currentScore = max(0, ceilingScore - fatigueImpact)

        return IntraDayReadiness(
            currentScore: currentScore,
            baselineScore: baselineScore,
            ceilingScore: ceilingScore,
            fatigueImpact: fatigueImpact,
            recoveryPercentage: 1.0 - (Double(fatigueImpact) / 50.0),
            timeToFullRecovery: latestRecoveryPoint.timeIntervalSince(now),
            recoveryPoint: latestRecoveryPoint
        )
    }

    // MARK: - Mathematical Models

    /// Assigns a "Fatigue Points" value to a workout (0-50 scale).
    private func calculateWorkoutFatigueLoad(_ workout: WorkoutData) -> Double {
        let durationHours = workout.duration / 3600.0

        var basePoints: Double
        switch workout.workoutType {
        case .running: basePoints = 25.0
        case .cycling: basePoints = 20.0
        case .swimming: basePoints = 22.0
        case .functionalStrengthTraining: basePoints = 18.0
        default: basePoints = 15.0
        }

        var intensityMultiplier = 1.0
        if let avgHR = workout.averageHeartRate {
            if avgHR > 160 { intensityMultiplier = 1.5 }
            else if avgHR > 140 { intensityMultiplier = 1.2 }
            else if avgHR < 120 { intensityMultiplier = 0.8 }
        }

        return basePoints * durationHours * intensityMultiplier
    }

    /// Determines the recovery half-life in seconds based on workout intensity.
    private func determineHalfLife(for workout: WorkoutData) -> Double {
        if let hr = workout.averageHeartRate, hr > 160 {
            return 10 * 3600 // Hard sessions: 10-hour half-life
        }
        if workout.duration > 2 * 3600 {
            return 8 * 3600 // Long sessions: 8-hour half-life
        }
        return 6 * 3600 // Moderate sessions: 6-hour half-life
    }
}
