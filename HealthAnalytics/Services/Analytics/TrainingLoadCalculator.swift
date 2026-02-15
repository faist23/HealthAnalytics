//
//  TrainingLoadCalculator.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import Foundation
import SwiftUI
import HealthKit

struct TrainingLoadCalculator {
    
    // MARK: - Training Load Models
    
    struct TrainingLoadSummary {
        let acuteLoad: Double      // Last 7 days average
        let chronicLoad: Double    // Last 28 days average
        let acuteChronicRatio: Double
        let status: LoadStatus
        let recommendation: String
        
        // Enhanced EWMA-based metrics
        let ewmaAcuteLoad: Double      // EWMA with 7-day time constant
        let ewmaChronicLoad: Double    // EWMA with 42-day time constant
        let ewmaRatio: Double          // EWMA-based acute:chronic ratio
        
        // Advanced injury risk indicators
        let monotony: Double           // Training variety (lower = more variety)
        let strain: Double             // Load × Monotony
        let weeklyLoadChange: Double   // % change from previous week
        
        enum LoadStatus {
            case fresh          // ACR < 0.8
            case optimal        // ACR 0.8-1.3
            case fatigued       // ACR 1.3-1.5
            case overreaching   // ACR > 1.5
            
            var color: Color {
                switch self {
                case .fresh: return .blue
                case .optimal: return .green
                case .fatigued: return .orange
                case .overreaching: return .red
                }
            }
            
            var emoji: String {
                switch self {
                case .fresh: return "💤"
                case .optimal: return "✅"
                case .fatigued: return "⚠️"
                case .overreaching: return "🚨"
                }
            }
        }
    }
    
    struct DailyLoad {
        let date: Date
        let load: Double
        let source: String // "workout", "steps", etc.
    }
    
    // MARK: - Calculate Training Load
    
    /// Calculates training load based on workouts and activity
    func calculateTrainingLoad(
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity],
        stepData: [HealthDataPoint]
    ) -> TrainingLoadSummary? {
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Calculate daily loads
        var dailyLoads: [Date: Double] = [:]
        
        // Process HealthKit workouts
        for workout in healthKitWorkouts {
            let day = calendar.startOfDay(for: workout.startDate)
            let load = calculateWorkoutLoad(workout)
            dailyLoads[day, default: 0] += load
        }
        
        // Process Strava activities
        for activity in stravaActivities {
            guard let startDate = activity.startDateFormatted else { continue }
            let day = calendar.startOfDay(for: startDate)
            let load = calculateStravaLoad(activity)
            dailyLoads[day, default: 0] += load
        }
        
        // Add light load for high step days (10k+ steps = bonus load)
        for step in stepData {
            let day = calendar.startOfDay(for: step.date)
            if step.value >= 10000, dailyLoads[day] == nil {
                // Only add step load if no workout that day
                dailyLoads[day] = (step.value - 10000) / 5000.0 // Each 5k steps over 10k = 1 load point
            }
        }
        
        // Calculate acute load (last 7 days average)
        var acuteLoadSum: Double = 0
        var acuteDays = 0
        
        for i in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            acuteLoadSum += dailyLoads[day] ?? 0
            acuteDays += 1
        }
        
        let acuteLoad = acuteDays > 0 ? acuteLoadSum / Double(acuteDays) : 0
        
        // Calculate chronic load (last 28 days average)
        var chronicLoadSum: Double = 0
        var chronicDays = 0
        
        for i in 0..<28 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            chronicLoadSum += dailyLoads[day] ?? 0
            chronicDays += 1
        }
        
        let chronicLoad = chronicDays > 0 ? chronicLoadSum / Double(chronicDays) : 0
        
        guard chronicLoad > 0 else { return nil }
        
        // Calculate acute:chronic ratio
        let acr = acuteLoad / chronicLoad
        
        // ENHANCED: Calculate EWMA-based loads
        let (ewmaAcute, ewmaChronic) = calculateEWMALoads(dailyLoads: dailyLoads, today: today)
        let ewmaRatio = ewmaChronic > 0 ? ewmaAcute / ewmaChronic : acr
        
        // ENHANCED: Calculate monotony and strain
        let monotony = calculateMonotony(dailyLoads: dailyLoads, days: 7, today: today)
        let strain = acuteLoad * monotony
        
        // ENHANCED: Calculate week-over-week load change
        let weeklyLoadChange = calculateWeeklyLoadChange(dailyLoads: dailyLoads, today: today)
        
        // Determine status and recommendation (prioritize EWMA ratio)
        let status: TrainingLoadSummary.LoadStatus
        let recommendation: String
        
        let primaryRatio = ewmaRatio // Use EWMA ratio as primary indicator
        
        if primaryRatio < 0.8 {
            status = .fresh
            recommendation = "You're well-rested. Good time for hard training or racing."
        } else if primaryRatio <= 1.3 {
            status = .optimal
            recommendation = "Training load is in the optimal range. Keep up the good work!"
        } else if primaryRatio <= 1.5 {
            status = .fatigued
            recommendation = "Training load is high. Consider adding recovery days."
        } else {
            status = .overreaching
            recommendation = "High risk of overtraining. Prioritize rest and recovery."
        }
        
        print("📊 Training Load Analysis:")
        print("   Acute Load (7d avg): \(String(format: "%.1f", acuteLoad))")
        print("   Chronic Load (28d avg): \(String(format: "%.1f", chronicLoad))")
        print("   ACR: \(String(format: "%.2f", acr))")
        print("   EWMA Acute: \(String(format: "%.1f", ewmaAcute))")
        print("   EWMA Chronic: \(String(format: "%.1f", ewmaChronic))")
        print("   EWMA Ratio: \(String(format: "%.2f", ewmaRatio))")
        print("   Monotony: \(String(format: "%.2f", monotony))")
        print("   Strain: \(String(format: "%.1f", strain))")
        print("   Weekly Change: \(String(format: "%.1f", weeklyLoadChange))%")
        print("   Status: \(status)")
        
        return TrainingLoadSummary(
            acuteLoad: acuteLoad,
            chronicLoad: chronicLoad,
            acuteChronicRatio: acr,
            status: status,
            recommendation: recommendation,
            ewmaAcuteLoad: ewmaAcute,
            ewmaChronicLoad: ewmaChronic,
            ewmaRatio: ewmaRatio,
            monotony: monotony,
            strain: strain,
            weeklyLoadChange: weeklyLoadChange
        )
    }
    
    // MARK: - Helper Methods
    
    private func calculateWorkoutLoad(_ workout: WorkoutData) -> Double {
        // Training Stress Score (TSS) estimation
        let durationHours = workout.duration / 3600.0
        
        // Base load on workout type and duration
        let baseLoad: Double
        
        switch workout.workoutType {
        case .running:
            // Running: ~50-80 TSS per hour depending on intensity
            baseLoad = durationHours * 65
            
        case .cycling:
            // Cycling: ~60-100 TSS per hour
            baseLoad = durationHours * 75
            
        case .swimming:
            baseLoad = durationHours * 70
            
        case .hiking, .walking:
            baseLoad = durationHours * 30
            
        case .functionalStrengthTraining, .traditionalStrengthTraining:
            baseLoad = durationHours * 50
            
        default:
            baseLoad = durationHours * 50
        }
        
        return baseLoad
    }
    
    private func calculateStravaLoad(_ activity: StravaActivity) -> Double {
        let durationHours = Double(activity.movingTime) / 3600.0
        
        // Use suffer score if available (Strava's built-in load metric)
        if let sufferScore = activity.sufferScore {
            return Double(sufferScore)  // Convert from Double? to Double
        }
        
        // Otherwise estimate based on type and duration
        let baseLoad: Double
        
        switch activity.type {
        case "Run":
            baseLoad = durationHours * 65
        case "Ride", "VirtualRide":
            baseLoad = durationHours * 75
        case "Swim":
            baseLoad = durationHours * 70
        case "Hike", "Walk":
            baseLoad = durationHours * 30
        default:
            baseLoad = durationHours * 50
        }
        
        return baseLoad
    }
    
    func calculateEWMA(currentValue: Double, previousAverage: Double, timeConstant: Int) -> Double {
        let alpha = 2.0 / (Double(timeConstant) + 1.0)
        return (currentValue * alpha) + (previousAverage * (1.0 - alpha))
    }
    
    func getActivityLoad(activity: StravaActivity) -> Double {
        let durationMinutes = Double(activity.movingTime) / 60.0
        
        // 1. Prioritize Power
        if let power = activity.averageWatts, power > 0 {
            // Simple Normalized Power Proxy: intensity^2 * duration
            // Assuming a baseline FTP or relative intensity
            let intensityFactor = power / 200.0 // 200 is a placeholder baseline
            return (intensityFactor * intensityFactor) * durationMinutes
        }
        
        // 2. Fallback to Heart Rate
        if let hr = activity.averageHeartrate, hr > 0 {
            let hrFactor = (hr - 60) / 100.0 // Intensity above baseline
            return (hrFactor * hrFactor) * durationMinutes
        }
        
        // 3. Fallback for Core/Maintenance
        if activity.type == "WeightTraining" || activity.type == "Yoga" {
            return durationMinutes * 0.2 // Minimal toll
        }
        
        return durationMinutes * 0.5 // Default
    }
    
    // MARK: - Enhanced Load Calculation Methods
    
    /// Calculates EWMA-based acute and chronic training loads
    /// EWMA is more responsive to recent changes than simple rolling averages
    private func calculateEWMALoads(dailyLoads: [Date: Double], today: Date) -> (acute: Double, chronic: Double) {
        let calendar = Calendar.current
        
        // Time constants: 7 days for acute, 42 days for chronic (6 weeks)
        let acuteTimeConstant = 7.0
        let chronicTimeConstant = 42.0
        
        var ewmaAcute: Double = 0
        var ewmaChronic: Double = 0
        
        // Calculate EWMA going backwards from today
        // We need at least 42 days of data for meaningful chronic load
        for i in 0..<42 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let load = dailyLoads[day] ?? 0
            
            // Update acute EWMA (last 7 days weighted)
            if i < 7 {
                let alpha = 2.0 / (acuteTimeConstant + 1.0)
                ewmaAcute = (load * alpha) + (ewmaAcute * (1.0 - alpha))
            }
            
            // Update chronic EWMA (all 42 days weighted)
            let alphaC = 2.0 / (chronicTimeConstant + 1.0)
            ewmaChronic = (load * alphaC) + (ewmaChronic * (1.0 - alphaC))
        }
        
        return (ewmaAcute, ewmaChronic)
    }
    
    /// Calculates training monotony - lack of variety in training load
    /// Monotony = average load / standard deviation
    /// High monotony (>2.0) + high load = high injury risk
    private func calculateMonotony(dailyLoads: [Date: Double], days: Int, today: Date) -> Double {
        let calendar = Calendar.current
        var loads: [Double] = []
        
        for i in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            loads.append(dailyLoads[day] ?? 0)
        }
        
        guard loads.count > 1 else { return 1.0 }
        
        let mean = loads.reduce(0, +) / Double(loads.count)
        let variance = loads.map { pow($0 - mean, 2) }.reduce(0, +) / Double(loads.count)
        let stdDev = sqrt(variance)
        
        // Avoid division by zero
        guard stdDev > 0 else { return 1.0 }
        
        return mean / stdDev
    }
    
    /// Calculates week-over-week load change percentage
    /// Rapid increases (>20%) are associated with higher injury risk
    private func calculateWeeklyLoadChange(dailyLoads: [Date: Double], today: Date) -> Double {
        let calendar = Calendar.current
        
        // Current week (last 7 days)
        var currentWeekLoad: Double = 0
        for i in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            currentWeekLoad += dailyLoads[day] ?? 0
        }
        
        // Previous week (days 7-13)
        var previousWeekLoad: Double = 0
        for i in 7..<14 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            previousWeekLoad += dailyLoads[day] ?? 0
        }
        
        guard previousWeekLoad > 0 else { return 0 }
        
        return ((currentWeekLoad - previousWeekLoad) / previousWeekLoad) * 100
    }
}
