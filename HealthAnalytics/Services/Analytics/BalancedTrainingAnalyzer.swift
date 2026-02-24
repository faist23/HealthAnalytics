//
//  BalancedTrainingAnalyzer.swift
//  HealthAnalytics
//
//  Analyzes training balance between aerobic/endurance and strength work
//  Research: Combining CRF + muscle strength reduces mortality more than either alone
//  Helps cyclists avoid single-modality training trap
//

import Foundation
import SwiftUI
import HealthKit

struct BalancedTrainingAnalyzer {
    
    // MARK: - Training Balance Models
    
    /// Weekly training balance summary
    struct TrainingBalance {
        let enduranceMinutes: Double          // Cycling, running, swimming, etc.
        let strengthMinutes: Double           // Strength training, core work
        let mobilityMinutes: Double           // Yoga, stretching
        let totalMinutes: Double
        
        let endurancePercentage: Double       // % of total training
        let strengthPercentage: Double
        let mobilityPercentage: Double
        
        let balance: BalanceStatus
        let trend: Trend
        let recommendation: String
        let researchInsight: String
        
        // Detailed activity breakdown
        let activityBreakdown: ActivityBreakdown
        
        enum BalanceStatus {
            case optimal                // Good mix of endurance + strength
            case enduranceDominant      // >90% endurance, lacking strength
            case strengthDominant       // >70% strength, lacking endurance
            case missingStrength        // No strength work in 14+ days
            case missingEndurance       // No endurance work in 7+ days
            case needsMobility          // No mobility work
            
            var label: String {
                switch self {
                case .optimal: return "Well-Balanced"
                case .enduranceDominant: return "Endurance-Heavy"
                case .strengthDominant: return "Strength-Heavy"
                case .missingStrength: return "Missing Strength"
                case .missingEndurance: return "Missing Endurance"
                case .needsMobility: return "Needs Mobility"
                }
            }
            
            var color: Color {
                switch self {
                case .optimal: return .green
                case .enduranceDominant, .strengthDominant: return .yellow
                case .missingStrength, .missingEndurance: return .orange
                case .needsMobility: return .blue
                }
            }
            
            var emoji: String {
                switch self {
                case .optimal: return "⚖️"
                case .enduranceDominant: return "🚴"
                case .strengthDominant: return "💪"
                case .missingStrength: return "⚠️"
                case .missingEndurance: return "⚠️"
                case .needsMobility: return "🧘"
                }
            }
        }
        
        enum Trend {
            case balancing       // Moving toward better balance
            case unbalancing     // Becoming more one-sided
            case stable          // Maintaining current pattern
            
            var emoji: String {
                switch self {
                case .balancing: return "✅"
                case .unbalancing: return "⚠️"
                case .stable: return "➡️"
                }
            }
        }
    }
    
    /// Detailed activity type breakdown
    struct ActivityBreakdown {
        let cycling: Double          // Minutes
        let running: Double
        let swimming: Double
        let strengthTraining: Double
        let coreWork: Double
        let yoga: Double
        let other: Double
        
        var topActivities: [(name: String, minutes: Double)] {
            let activities = [
                ("Cycling", cycling),
                ("Running", running),
                ("Swimming", swimming),
                ("Strength", strengthTraining),
                ("Core", coreWork),
                ("Yoga", yoga),
                ("Other", other)
            ]
            return activities
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
        }
    }
    
    /// Historical balance point for trending
    struct BalanceSnapshot {
        let date: Date
        let endurancePercentage: Double
        let strengthPercentage: Double
    }
    
    // MARK: - Analysis Function
    
    /// Analyze training balance over recent weeks
    func analyzeTrainingBalance(
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> TrainingBalance? {
        
        print("⚖️ Analyzing Training Balance...")
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Combine all workouts
        var allWorkouts = healthKitWorkouts
        
        // Add Strava activities not already in HealthKit
        for activity in stravaActivities {
            if let workout = WorkoutData(from: activity) {
                allWorkouts.append(workout)
            }
        }
        
        // Filter to last 14 days for balance analysis
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today)!
        let recentWorkouts = allWorkouts.filter { $0.startDate >= twoWeeksAgo }
        
        guard !recentWorkouts.isEmpty else {
            print("   ⚠️ No workout data for balance analysis")
            return nil
        }
        
        // Categorize workouts
        var enduranceMinutes: Double = 0
        var strengthMinutes: Double = 0
        var mobilityMinutes: Double = 0
        
        var cyclingMinutes: Double = 0
        var runningMinutes: Double = 0
        var swimmingMinutes: Double = 0
        var strengthTrainingMinutes: Double = 0
        var coreMinutes: Double = 0
        var yogaMinutes: Double = 0
        var otherMinutes: Double = 0
        
        // Track days since last strength/endurance session
        var lastStrengthDate: Date?
        var lastEnduranceDate: Date?
        
        for workout in recentWorkouts {
            let minutes = workout.duration / 60.0
            
            switch workout.workoutType {
            // Endurance activities
            case .cycling:
                enduranceMinutes += minutes
                cyclingMinutes += minutes
                lastEnduranceDate = max(lastEnduranceDate ?? workout.startDate, workout.startDate)
                
            case .running:
                enduranceMinutes += minutes
                runningMinutes += minutes
                lastEnduranceDate = max(lastEnduranceDate ?? workout.startDate, workout.startDate)
                
            case .swimming:
                enduranceMinutes += minutes
                swimmingMinutes += minutes
                lastEnduranceDate = max(lastEnduranceDate ?? workout.startDate, workout.startDate)
                
            case .walking, .hiking, .rowing, .elliptical, .stairClimbing:
                enduranceMinutes += minutes
                otherMinutes += minutes
                lastEnduranceDate = max(lastEnduranceDate ?? workout.startDate, workout.startDate)
                
            // Strength activities
            case .functionalStrengthTraining, .traditionalStrengthTraining:
                strengthMinutes += minutes
                strengthTrainingMinutes += minutes
                lastStrengthDate = max(lastStrengthDate ?? workout.startDate, workout.startDate)
                
            case .coreTraining:
                strengthMinutes += minutes
                coreMinutes += minutes
                lastStrengthDate = max(lastStrengthDate ?? workout.startDate, workout.startDate)
                
            // Mobility/recovery activities
            case .yoga:
                mobilityMinutes += minutes
                yogaMinutes += minutes
                
            default:
                otherMinutes += minutes
            }
        }
        
        let totalMinutes = enduranceMinutes + strengthMinutes + mobilityMinutes
        
        guard totalMinutes > 0 else {
            print("   ⚠️ No categorizable training data")
            return nil
        }
        
        // Calculate percentages
        let endurancePercentage = (enduranceMinutes / totalMinutes) * 100
        let strengthPercentage = (strengthMinutes / totalMinutes) * 100
        let mobilityPercentage = (mobilityMinutes / totalMinutes) * 100
        
        // Determine balance status
        let daysSinceStrength = lastStrengthDate.map { calendar.dateComponents([.day], from: $0, to: today).day ?? 999 } ?? 999
        let daysSinceEndurance = lastEnduranceDate.map { calendar.dateComponents([.day], from: $0, to: today).day ?? 999 } ?? 999
        
        let balance: TrainingBalance.BalanceStatus
        if daysSinceStrength >= 14 {
            balance = .missingStrength
        } else if daysSinceEndurance >= 7 {
            balance = .missingEndurance
        } else if strengthPercentage < 10 && endurancePercentage > 90 {
            balance = .enduranceDominant
        } else if strengthPercentage > 70 {
            balance = .strengthDominant
        } else if mobilityMinutes == 0 && totalMinutes > 300 {
            balance = .needsMobility
        } else if strengthPercentage >= 15 && strengthPercentage <= 40 {
            balance = .optimal
        } else {
            balance = .enduranceDominant  // Default for cyclists
        }
        
        // Calculate trend (compare to previous 14 days)
        let trend = calculateBalanceTrend(
            workouts: allWorkouts,
            currentEndurancePct: endurancePercentage,
            currentStrengthPct: strengthPercentage,
            today: today
        )
        
        // Generate recommendation
        let recommendation = generateBalanceRecommendation(
            balance: balance,
            strengthPct: strengthPercentage,
            endurancePct: endurancePercentage,
            mobilityMinutes: mobilityMinutes,
            daysSinceStrength: daysSinceStrength
        )
        
        // Research insight
        let researchInsight = "Research shows combining cardiorespiratory fitness AND muscle strength reduces mortality more than either alone."
        
        // Create activity breakdown
        let activityBreakdown = ActivityBreakdown(
            cycling: cyclingMinutes,
            running: runningMinutes,
            swimming: swimmingMinutes,
            strengthTraining: strengthTrainingMinutes,
            coreWork: coreMinutes,
            yoga: yogaMinutes,
            other: otherMinutes
        )
        
        print("   Endurance: \(String(format: "%.0f", enduranceMinutes)) min (\(String(format: "%.0f", endurancePercentage))%)")
        print("   Strength: \(String(format: "%.0f", strengthMinutes)) min (\(String(format: "%.0f", strengthPercentage))%)")
        print("   Mobility: \(String(format: "%.0f", mobilityMinutes)) min (\(String(format: "%.0f", mobilityPercentage))%)")
        print("   Balance: \(balance.label)")
        print("   Days since strength: \(daysSinceStrength)")
        
        return TrainingBalance(
            enduranceMinutes: enduranceMinutes,
            strengthMinutes: strengthMinutes,
            mobilityMinutes: mobilityMinutes,
            totalMinutes: totalMinutes,
            endurancePercentage: endurancePercentage,
            strengthPercentage: strengthPercentage,
            mobilityPercentage: mobilityPercentage,
            balance: balance,
            trend: trend,
            recommendation: recommendation,
            researchInsight: researchInsight,
            activityBreakdown: activityBreakdown
        )
    }
    
    // MARK: - Helper Methods
    
    /// Calculate trend by comparing current vs previous 14-day period
    private func calculateBalanceTrend(
        workouts: [WorkoutData],
        currentEndurancePct: Double,
        currentStrengthPct: Double,
        today: Date
    ) -> TrainingBalance.Trend {
        
        let calendar = Calendar.current
        
        // Previous 14 days (days 14-27)
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: today)!
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today)!
        
        let previousWorkouts = workouts.filter { $0.startDate >= fourWeeksAgo && $0.startDate < twoWeeksAgo }
        
        guard !previousWorkouts.isEmpty else {
            return .stable
        }
        
        var prevEndurance: Double = 0
        var prevStrength: Double = 0
        
        for workout in previousWorkouts {
            let minutes = workout.duration / 60.0
            
            switch workout.workoutType {
            case .cycling, .running, .swimming, .walking, .hiking, .rowing, .elliptical, .stairClimbing:
                prevEndurance += minutes
            case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining:
                prevStrength += minutes
            default:
                break
            }
        }
        
        let prevTotal = prevEndurance + prevStrength
        guard prevTotal > 0 else { return .stable }
        
        let prevStrengthPct = (prevStrength / prevTotal) * 100
        
        // If strength percentage increased by 5+ points, we're balancing
        // If it decreased by 5+ points, we're unbalancing
        let strengthChange = currentStrengthPct - prevStrengthPct
        
        if abs(strengthChange) < 5 {
            return .stable
        } else if strengthChange > 0 && currentStrengthPct < 50 {
            // Increasing strength (good if we were low)
            return prevStrengthPct < 15 ? .balancing : .stable
        } else if strengthChange < 0 && prevStrengthPct >= 15 {
            // Decreasing strength (bad if we had good balance)
            return .unbalancing
        }
        
        return .stable
    }
    
    /// Generate personalized balance recommendation
    private func generateBalanceRecommendation(
        balance: TrainingBalance.BalanceStatus,
        strengthPct: Double,
        endurancePct: Double,
        mobilityMinutes: Double,
        daysSinceStrength: Int
    ) -> String {
        
        switch balance {
        case .optimal:
            if mobilityMinutes < 30 {
                return "Excellent endurance-strength balance. Consider adding 1-2 weekly mobility sessions."
            } else {
                return "Optimal training balance. Maintain this mix for long-term health and performance."
            }
            
        case .enduranceDominant:
            if strengthPct < 5 {
                return "Add 2 weekly strength sessions (30-45 min each). Even minimal strength work improves outcomes."
            } else if strengthPct < 15 {
                return "Increase strength work to 15-20% of weekly volume for optimal balance."
            } else {
                return "Good endurance focus. Add one more strength session weekly for better balance."
            }
            
        case .missingStrength:
            return "No strength training in \(daysSinceStrength) days. Schedule 2-3 sessions this week to maintain muscle mass."
            
        case .missingEndurance:
            return "Limited cardio recently. Add 2-3 aerobic sessions to maintain cardiovascular fitness."
            
        case .strengthDominant:
            return "Heavy strength focus. Add 2-3 endurance sessions weekly for cardiovascular health."
            
        case .needsMobility:
            return "Strong training volume. Add 20-30 min weekly mobility work to support recovery."
        }
    }
    
    /// Get recommended weekly training split
    func getRecommendedSplit(currentBalance: TrainingBalance) -> (endurance: String, strength: String, mobility: String) {
        
        switch currentBalance.balance {
        case .optimal:
            return (
                endurance: "4-5 sessions",
                strength: "2-3 sessions",
                mobility: "1-2 sessions"
            )
            
        case .enduranceDominant, .missingStrength:
            return (
                endurance: "3-4 sessions",
                strength: "2-3 sessions (PRIORITY)",
                mobility: "1-2 sessions"
            )
            
        case .strengthDominant, .missingEndurance:
            return (
                endurance: "4-5 sessions (PRIORITY)",
                strength: "2 sessions",
                mobility: "1-2 sessions"
            )
            
        case .needsMobility:
            return (
                endurance: "4-5 sessions",
                strength: "2-3 sessions",
                mobility: "2-3 sessions (PRIORITY)"
            )
        }
    }
}
