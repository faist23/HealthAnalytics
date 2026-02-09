//
//  PredictiveReadinessService.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/1/26.
//


import Foundation
import HealthKit
import SwiftUI

struct PredictiveReadinessService {
    
    enum TrainingState {
        case undertraining // ACWR < 0.8
        case optimizing    // ACWR 0.8 - 1.3
        case overreaching  // ACWR 1.3 - 1.5
        case dangerZone    // ACWR > 1.5
        
        var label: String {
            switch self {
            case .undertraining: return "Undertraining"
            case .optimizing: return "Optimizing"
            case .overreaching: return "Overreaching"
            case .dangerZone: return "Danger Zone"
            }
        }
        
        var color: Color {
            switch self {
            case .optimizing: return .green
            case .overreaching: return .orange
            case .dangerZone: return .red
            default: return .blue
            }
        }
    }
    
    struct ReadinessAssessment {
        let acwr: Double
        let state: TrainingState
        let recommendation: String
        let primaryFactor: String
    }
    
    /// Calculates readiness using EWMA for Acute (7-day) and Chronic (28-day) loads
    func calculateReadiness(
        stravaActivities: [StravaActivity],
        healthKitWorkouts: [WorkoutData]
    ) -> ReadinessAssessment {
        
        let calendar = Calendar.current
        let now = Date()
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        
        // 1. Calculate daily loads for the last 60 days
        var dailyLoads: [Date: Double] = [:]
        
        // Process Strava (Prioritizing Power)
        for activity in stravaActivities {
            guard let date = activity.startDateFormatted, date >= sixtyDaysAgo else { continue }
            let day = calendar.startOfDay(for: date)
            let load = calculateActivityLoad(activity: activity)
            dailyLoads[day, default: 0] += load
        }
        
        // Process HealthKit (Fallback for Core/Maintenance)
        for workout in healthKitWorkouts {
            guard workout.startDate >= sixtyDaysAgo else { continue }
            let day = calendar.startOfDay(for: workout.startDate)
            // If we already have Strava data for this day, skip or add only if distinct
            // For now, let's assume if it's not a 'Run' or 'Ride', it's maintenance/core
            if workout.workoutType != .running && workout.workoutType != .cycling {
                let load = Double(workout.duration / 60.0) * 0.2 // Core weighting
                dailyLoads[day, default: 0] += load
            }
        }
        
        // 2. Calculate EWMA
        var acuteLoad: Double = 0
        var chronicLoad: Double = 0
        
        let sortedDates = dailyLoads.keys.sorted()
        for date in sortedDates {
            let load = dailyLoads[date] ?? 0
            
            // Acute (7-day decay)
            let alphaAcute = 2.0 / (7.0 + 1.0)
            acuteLoad = (load * alphaAcute) + (acuteLoad * (1.0 - alphaAcute))
            
            // Chronic (28-day decay)
            let alphaChronic = 2.0 / (28.0 + 1.0)
            chronicLoad = (load * alphaChronic) + (chronicLoad * (1.0 - alphaChronic))
        }
        
        // 3. Determine Ratio and State
        let ratio = chronicLoad > 0 ? (acuteLoad / chronicLoad) : 0
        let state: TrainingState
        
        if ratio < 0.8 { state = .undertraining }
        else if ratio <= 1.3 { state = .optimizing }
        else if ratio <= 1.5 { state = .overreaching }
        else { state = .dangerZone }
        
        return ReadinessAssessment(
            acwr: ratio,
            state: state,
            recommendation: generateRecommendation(state: state),
            primaryFactor: "Load Ratio: \(String(format: "%.2f", ratio))"
        )
    }
    
    private func calculateActivityLoad(activity: StravaActivity) -> Double {
        let durationMinutes = Double(activity.movingTime) / 60.0
        
        // Weighting Core/Maintenance very low
        if activity.type == "WeightTraining" || activity.type == "Yoga" {
            return durationMinutes * 0.2
        }
        
        // Prioritize Power (Sweet Spot / Intervals)
        if let power = activity.averageWatts, power > 0 {
            let intensityFactor = power / 200.0 // Placeholder FTP baseline
            return (intensityFactor * intensityFactor) * durationMinutes
        }
        
        // Fallback to Heart Rate
        if let hr = activity.averageHeartrate, hr > 0 {
            let hrIntensity = (hr - 60) / 100.0
            return (hrIntensity * hrIntensity) * durationMinutes
        }
        
        return durationMinutes * 0.5
    }
    
    private func generateRecommendation(state: TrainingState) -> String {
        switch state {
        case .undertraining: return "Consider increasing intensity to build fitness."
        case .optimizing: return "Optimal training zone. Ready for planned efforts."
        case .overreaching: return "Pace is high. Monitor fatigue levels closely."
        case .dangerZone: return "Significant fatigue spike. Prioritize recovery today."
        }
    }
    
    struct ACWRDay: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
    
    func calculate7DayTrend(
        stravaActivities: [StravaActivity],
        healthKitWorkouts: [WorkoutData]
    ) -> [ACWRDay] {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        var trend: [ACWRDay] = []
        
        // Calculate the assessment for each of the last 7 days
        for dayOffset in (0...6).reversed() {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            
            // Filter data up to the target date to simulate "standing" at that point in time
            let filteredStrava = stravaActivities.filter { ($0.startDateFormatted ?? Date()) <= targetDate }
            let filteredHK = healthKitWorkouts.filter { $0.startDate <= targetDate }
            
            let assessment = calculateReadiness(stravaActivities: filteredStrava, healthKitWorkouts: filteredHK)
            trend.append(ACWRDay(date: targetDate, value: assessment.acwr))
        }
        
        return trend
    }
    
    struct AgingInsight {
        let recoveryShiftDays: Double
        let intensityThresholdChange: Double // % change in what is considered 'High Intensity'
    }

    func calculateAgingContext(allWorkouts: [StoredWorkout]) -> AgingInsight? {
        // Filter workouts to compare 'Early Decade' (2016-2018) vs 'Current' (2024-2026)
        let historicalWorkouts = allWorkouts.filter { $0.startDate < .yearsAgo(5) }
        let recentWorkouts = allWorkouts.filter { $0.startDate > .monthsAgo(6) }
        
        // Calculate the average recovery time needed after a 'High Load' day
        let historicalRecovery = calculateAvgRecovery(for: historicalWorkouts)
        let currentRecovery = calculateAvgRecovery(for: recentWorkouts)
        
        return AgingInsight(
            recoveryShiftDays: currentRecovery - historicalRecovery,
            intensityThresholdChange: calculateThresholdShift(old: historicalWorkouts, new: recentWorkouts)
        )
    }
    
    func generateAgingInsight(allWorkouts: [StoredWorkout]) -> AgingInsight? {
        // 1. Establish the "Youth Baseline" (First 2 years of data)
        let earliestDate = allWorkouts.map { $0.startDate }.min() ?? .now
        let youthWorkouts = allWorkouts.filter { $0.startDate < earliestDate.addingTimeInterval(63072000) } // 2 years
        
        // 2. Establish "Current Reality" (Last 6 months)
        let currentWorkouts = allWorkouts.filter { $0.startDate > .monthsAgo(6) }
        
        guard youthWorkouts.count > 10, currentWorkouts.count > 10 else { return nil }
        
        // 3. Compare Average Recovery (Gaps between high-intensity efforts)
        let historicalRecovery = calculateAvgRecovery(for: youthWorkouts.filter { ($0.averagePower ?? 0) > 150 })
        let currentRecovery = calculateAvgRecovery(for: currentWorkouts.filter { ($0.averagePower ?? 0) > 150 })
        
        let shift = currentRecovery - historicalRecovery
        
        // Only return if there is a significant shift (e.g., > 0.5 days extra recovery needed)
        return AgingInsight(
            recoveryShiftDays: shift,
            intensityThresholdChange: calculateThresholdShift(old: youthWorkouts, new: currentWorkouts)
        )
    }

    private func calculateAvgRecovery(for workouts: [StoredWorkout]) -> Double {
        guard workouts.count > 1 else { return 0 }
        let sorted = workouts.sorted { $0.startDate < $1.startDate }
        var gaps: [TimeInterval] = []
        
        for i in 1..<sorted.count {
            let gap = sorted[i].startDate.timeIntervalSince(sorted[i-1].startDate)
            gaps.append(gap)
        }
        
        // Returns average gap in days
        return (gaps.reduce(0, +) / Double(gaps.count)) / 86400.0
    }

    private func calculateThresholdShift(old: [StoredWorkout], new: [StoredWorkout]) -> Double {
        let oldAvg = old.compactMap { $0.averagePower }.reduce(0, +) / Double(max(1, old.count))
        let newAvg = new.compactMap { $0.averagePower }.reduce(0, +) / Double(max(1, new.count))
        
        guard oldAvg > 0 else { return 0 }
        return ((newAvg - oldAvg) / oldAvg) * 100
    }
}
