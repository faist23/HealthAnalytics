//
//  METAnalyzer.swift
//  HealthAnalytics
//
//  MET-based activity analysis - evidence-based alternative to VO2 max focus
//  Research: Each MET increase correlates with 14-15% mortality reduction
//  Based on 750,000+ participant studies (99% of longevity research uses METs, not VO2 max)
//

import Foundation
import SwiftUI
import HealthKit

struct METAnalyzer {
    
    // MARK: - MET Models
    
    /// Weekly MET summary with intensity breakdown
    struct METSummary {
        let weeklyMETMinutes: Double          // Total MET-minutes per week
        let dailyAverageMETs: Double          // Average daily MET-minutes
        let lightActivityMinutes: Double      // <3.0 METs (slow walking)
        let moderateActivityMinutes: Double   // 3.0-5.9 METs (brisk walking)
        let vigorousActivityMinutes: Double   // ≥6.0 METs (jogging, cycling)
        
        let trend: Trend
        let status: ActivityStatus
        let recommendation: String
        let researchContext: String
        
        enum Trend {
            case improving      // Increasing MET capacity
            case stable         // Maintaining
            case declining      // Decreasing activity
            
            var emoji: String {
                switch self {
                case .improving: return "📈"
                case .stable: return "➡️"
                case .declining: return "📉"
                }
            }
            
            var color: Color {
                switch self {
                case .improving: return .green
                case .stable: return .blue
                case .declining: return .orange
                }
            }
        }
        
        enum ActivityStatus {
            case excellent      // >3000 MET-min/week (WHO recommendation: 600-1500)
            case good           // 1500-3000 MET-min/week
            case moderate       // 600-1500 MET-min/week (minimum WHO)
            case insufficient   // <600 MET-min/week
            
            var label: String {
                switch self {
                case .excellent: return "Excellent"
                case .good: return "Good"
                case .moderate: return "Moderate"
                case .insufficient: return "Below Target"
                }
            }
            
            var color: Color {
                switch self {
                case .excellent: return .green
                case .good: return .blue
                case .moderate: return .yellow
                case .insufficient: return .red
                }
            }
            
            var emoji: String {
                switch self {
                case .excellent: return "🌟"
                case .good: return "✅"
                case .moderate: return "📊"
                case .insufficient: return "⚠️"
                }
            }
        }
    }
    
    /// Daily MET breakdown
    struct DailyMETData: Identifiable {
        let id = UUID()
        let date: Date
        let totalMETMinutes: Double
        let lightMinutes: Double
        let moderateMinutes: Double
        let vigorousMinutes: Double
        let dominantIntensity: IntensityLevel
        
        enum IntensityLevel {
            case light, moderate, vigorous, mixed
            
            var color: Color {
                switch self {
                case .light: return .blue.opacity(0.6)
                case .moderate: return .orange.opacity(0.7)
                case .vigorous: return .red.opacity(0.8)
                case .mixed: return .purple.opacity(0.7)
                }
            }
        }
    }
    
    // MARK: - MET Calculation
    
    /// Calculate comprehensive MET summary for weekly activity
    func analyzeMETActivity(
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity],
        stepData: [HealthDataPoint]
    ) -> METSummary? {
        
        print("🏃 Analyzing MET Activity...")
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Calculate daily MET data for last 7 days
        var dailyMETData: [Date: (light: Double, moderate: Double, vigorous: Double)] = [:]
        
        // Process HealthKit workouts
        for workout in healthKitWorkouts {
            let day = calendar.startOfDay(for: workout.startDate)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day,
                  daysAgo >= 0, daysAgo < 7 else { continue }
            
            let metData = calculateMETForWorkout(workout)
            var existing = dailyMETData[day] ?? (0, 0, 0)
            existing.light += metData.light
            existing.moderate += metData.moderate
            existing.vigorous += metData.vigorous
            dailyMETData[day] = existing
        }
        
        // Process Strava activities
        for activity in stravaActivities {
            guard let startDate = activity.startDateFormatted else { continue }
            let day = calendar.startOfDay(for: startDate)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day,
                  daysAgo >= 0, daysAgo < 7 else { continue }
            
            let metData = calculateMETForStravaActivity(activity)
            var existing = dailyMETData[day] ?? (0, 0, 0)
            existing.light += metData.light
            existing.moderate += metData.moderate
            existing.vigorous += metData.vigorous
            dailyMETData[day] = existing
        }
        
        // Add step-based activity (for days without structured workouts)
        for step in stepData {
            let day = calendar.startOfDay(for: step.date)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day,
                  daysAgo >= 0, daysAgo < 7 else { continue }
            
            // Only add step-based METs if no workout that day
            if dailyMETData[day] == nil {
                let metMinutes = calculateMETFromSteps(steps: step.value)
                dailyMETData[day] = metMinutes
            }
        }
        
        // Aggregate weekly totals
        var weeklyLight: Double = 0
        var weeklyModerate: Double = 0
        var weeklyVigorous: Double = 0
        
        for (_, metData) in dailyMETData {
            weeklyLight += metData.light
            weeklyModerate += metData.moderate
            weeklyVigorous += metData.vigorous
        }
        
        let totalMETMinutes = weeklyLight + weeklyModerate + weeklyVigorous
        
        guard totalMETMinutes > 0 else {
            print("   ⚠️ No MET activity data available")
            return nil
        }
        
        let dailyAverage = totalMETMinutes / 7.0
        
        // Calculate trend (compare to previous week)
        let previousWeekMETs = calculatePreviousWeekMETs(
            workouts: healthKitWorkouts,
            activities: stravaActivities,
            stepData: stepData,
            today: today
        )
        
        let trend: METSummary.Trend
        if previousWeekMETs > 0 {
            let changePercent = ((totalMETMinutes - previousWeekMETs) / previousWeekMETs) * 100
            if changePercent > 10 {
                trend = .improving
            } else if changePercent < -10 {
                trend = .declining
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }
        
        // Determine status based on WHO guidelines
        let status: METSummary.ActivityStatus
        if totalMETMinutes >= 3000 {
            status = .excellent
        } else if totalMETMinutes >= 1500 {
            status = .good
        } else if totalMETMinutes >= 600 {
            status = .moderate
        } else {
            status = .insufficient
        }
        
        // Generate recommendation
        let recommendation = generateRecommendation(
            status: status,
            trend: trend,
            vigorousMinutes: weeklyVigorous,
            moderateMinutes: weeklyModerate
        )
        
        // Research context
        let researchContext = "Based on 750,000+ participant studies: Each MET increase = 14-15% mortality reduction"
        
        print("   Weekly MET-minutes: \(String(format: "%.0f", totalMETMinutes))")
        print("   Status: \(status.label)")
        print("   Trend: \(trend)")
        print("   Light: \(String(format: "%.0f", weeklyLight)) min")
        print("   Moderate: \(String(format: "%.0f", weeklyModerate)) min")
        print("   Vigorous: \(String(format: "%.0f", weeklyVigorous)) min")
        
        return METSummary(
            weeklyMETMinutes: totalMETMinutes,
            dailyAverageMETs: dailyAverage,
            lightActivityMinutes: weeklyLight,
            moderateActivityMinutes: weeklyModerate,
            vigorousActivityMinutes: weeklyVigorous,
            trend: trend,
            status: status,
            recommendation: recommendation,
            researchContext: researchContext
        )
    }
    
    // MARK: - Helper Methods
    
    /// Calculate MET-minutes for a HealthKit workout
    private func calculateMETForWorkout(_ workout: WorkoutData) -> (light: Double, moderate: Double, vigorous: Double) {
        let durationMinutes = workout.duration / 60.0
        
        // MET values by activity type (based on Compendium of Physical Activities)
        let metValue: Double
        let intensity: String
        
        switch workout.workoutType {
        case .running:
            // Running typically 7-12 METs depending on pace
            // If we have average HR, use it to estimate intensity
            if let hr = workout.averageHeartRate {
                if hr > 160 {
                    metValue = 11.0  // Hard running
                    intensity = "vigorous"
                } else if hr > 140 {
                    metValue = 9.0   // Moderate running
                    intensity = "vigorous"
                } else {
                    metValue = 6.0   // Easy running
                    intensity = "vigorous"
                }
            } else {
                metValue = 9.0  // Default moderate running
                intensity = "vigorous"
            }
            
        case .cycling:
            // Cycling 4-16 METs depending on intensity
            if let power = workout.averagePower {
                if power > 250 {
                    metValue = 14.0  // Hard cycling
                    intensity = "vigorous"
                } else if power > 200 {
                    metValue = 10.0  // Moderate cycling
                    intensity = "vigorous"
                } else if power > 150 {
                    metValue = 8.0   // Light cycling
                    intensity = "vigorous"
                } else {
                    metValue = 6.0   // Easy cycling
                    intensity = "moderate"
                }
            } else if let hr = workout.averageHeartRate {
                if hr > 160 {
                    metValue = 12.0
                    intensity = "vigorous"
                } else if hr > 140 {
                    metValue = 8.0
                    intensity = "vigorous"
                } else {
                    metValue = 6.0
                    intensity = "moderate"
                }
            } else {
                metValue = 8.0  // Default moderate cycling
                intensity = "vigorous"
            }
            
        case .swimming:
            metValue = 8.0  // Moderate lap swimming
            intensity = "vigorous"
            
        case .walking:
            metValue = 3.5  // Brisk walking
            intensity = "moderate"
            
        case .hiking:
            metValue = 6.0  // Hiking with moderate grade
            intensity = "moderate"
            
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining:
            metValue = 6.0  // Weight lifting, vigorous effort
            intensity = "vigorous"
            
        case .yoga:
            metValue = 3.0  // Hatha yoga
            intensity = "light"
            
        case .rowing:
            metValue = 9.0  // Rowing, vigorous
            intensity = "vigorous"
            
        case .elliptical:
            metValue = 7.0  // Elliptical, moderate
            intensity = "vigorous"
            
        case .stairClimbing:
            metValue = 8.0  // Stair climbing
            intensity = "vigorous"
            
        default:
            metValue = 5.0  // Default moderate activity
            intensity = "moderate"
        }
        
        let metMinutes = metValue * durationMinutes
        
        // Categorize by intensity
        switch intensity {
        case "light":
            return (light: metMinutes, moderate: 0, vigorous: 0)
        case "moderate":
            return (light: 0, moderate: metMinutes, vigorous: 0)
        case "vigorous":
            return (light: 0, moderate: 0, vigorous: metMinutes)
        default:
            return (light: 0, moderate: metMinutes, vigorous: 0)
        }
    }
    
    /// Calculate MET-minutes for Strava activity
    private func calculateMETForStravaActivity(_ activity: StravaActivity) -> (light: Double, moderate: Double, vigorous: Double) {
        let durationMinutes = Double(activity.movingTime) / 60.0
        
        let metValue: Double
        let intensity: String
        
        // Use average heart rate if available
        if let hr = activity.averageHeartrate {
            if hr > 160 {
                metValue = 11.0
                intensity = "vigorous"
            } else if hr > 140 {
                metValue = 8.0
                intensity = "vigorous"
            } else if hr > 120 {
                metValue = 6.0
                intensity = "moderate"
            } else {
                metValue = 4.0
                intensity = "moderate"
            }
        } else {
            // Fallback based on activity type
            switch activity.type {
            case "Run":
                metValue = 9.0
                intensity = "vigorous"
            case "Ride", "VirtualRide":
                metValue = 8.0
                intensity = "vigorous"
            case "Swim":
                metValue = 8.0
                intensity = "vigorous"
            case "Walk", "Hike":
                metValue = 5.0
                intensity = "moderate"
            case "WeightTraining":
                metValue = 6.0
                intensity = "vigorous"
            default:
                metValue = 5.0
                intensity = "moderate"
            }
        }
        
        let metMinutes = metValue * durationMinutes
        
        switch intensity {
        case "light":
            return (light: metMinutes, moderate: 0, vigorous: 0)
        case "moderate":
            return (light: 0, moderate: metMinutes, vigorous: 0)
        case "vigorous":
            return (light: 0, moderate: 0, vigorous: metMinutes)
        default:
            return (light: 0, moderate: metMinutes, vigorous: 0)
        }
    }
    
    /// Calculate MET-minutes from daily step count
    private func calculateMETFromSteps(steps: Double) -> (light: Double, moderate: Double, vigorous: Double) {
        // Rough estimation: 100 steps per minute = walking
        // 2000 steps ≈ 1 mile ≈ 20 minutes walking at 3 mph (3.5 METs)
        
        let estimatedWalkingMinutes = steps / 100.0
        let metValue = 3.5  // Brisk walking MET value
        let metMinutes = metValue * estimatedWalkingMinutes
        
        // Steps are generally moderate intensity
        return (light: 0, moderate: metMinutes, vigorous: 0)
    }
    
    /// Calculate previous week's MET-minutes for trend comparison
    private func calculatePreviousWeekMETs(
        workouts: [WorkoutData],
        activities: [StravaActivity],
        stepData: [HealthDataPoint],
        today: Date
    ) -> Double {
        let calendar = Calendar.current
        var totalMETs: Double = 0
        
        // Process workouts from days 7-13
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day,
                  daysAgo >= 7, daysAgo < 14 else { continue }
            
            let metData = calculateMETForWorkout(workout)
            totalMETs += metData.light + metData.moderate + metData.vigorous
        }
        
        // Process Strava activities from days 7-13
        for activity in activities {
            guard let startDate = activity.startDateFormatted else { continue }
            let day = calendar.startOfDay(for: startDate)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day,
                  daysAgo >= 7, daysAgo < 14 else { continue }
            
            let metData = calculateMETForStravaActivity(activity)
            totalMETs += metData.light + metData.moderate + metData.vigorous
        }
        
        return totalMETs
    }
    
    /// Generate personalized recommendation based on MET analysis
    private func generateRecommendation(
        status: METSummary.ActivityStatus,
        trend: METSummary.Trend,
        vigorousMinutes: Double,
        moderateMinutes: Double
    ) -> String {
        
        switch status {
        case .excellent:
            if trend == .improving {
                return "Outstanding activity level! Maintain balance between intensity and recovery."
            } else {
                return "Excellent weekly activity. Consider varying intensity for continued adaptation."
            }
            
        case .good:
            if vigorousMinutes < 75 {
                return "Good volume. WHO recommends 150 min moderate OR 75 min vigorous per week."
            } else {
                return "Strong activity level. Keep up the consistency."
            }
            
        case .moderate:
            if vigorousMinutes > 0 {
                return "Meeting minimum WHO guidelines. Consider adding 1-2 more vigorous sessions weekly."
            } else {
                return "Meeting minimums with moderate activity. Add vigorous sessions for greater benefits."
            }
            
        case .insufficient:
            return "Below WHO minimum (600 MET-min/week). Start with 150 min brisk walking weekly."
        }
    }
}

// Note: WorkoutData extension with init(from: StravaActivity) already exists in ReadinessAnalyzer.swift
