//
//  ReadinessAnalyzer.swift
//  HealthAnalytics
//
//  Revolutionary athlete-centric readiness system
//  Replaces CTL/ATL/TSB with meaningful, actionable insights
//

import Foundation
import SwiftUI
import HealthKit

struct ReadinessAnalyzer {
    
    // MARK: - Core Readiness Model
    
    /// Forward-looking trajectory
    struct TrajectoryPoint: Identifiable {
        let id = UUID()
        let date: Date
        let predictedReadiness: Int
        let confidence: Double        // 0-1
        let scenario: Scenario
        
        enum Scenario {
            case planned              // Based on planned training
            case ifRest              // If you take a rest day
            case ifModerate          // If you do easy training
            case ifHard              // If you do hard session
        }
    }
    
    /// The main readiness assessment - what athletes actually care about
    struct ReadinessScore {
        let score: Int                    // 0-100 scale
        let trend: Trend                  // Where you're heading
        let recommendation: String        // What to do today
        let confidence: Confidence        // How reliable is this
        let breakdown: ScoreBreakdown    // Why this score
        let trajectory: [TrajectoryPoint] // Next 7 days forecast
        
        enum Trend {
            case improving      // Getting stronger/fresher
            case maintaining    // Steady state
            case declining      // Accumulating fatigue
            case peaking        // Prime window for performance
            case recovering     // Coming back from hard block
            
            var emoji: String {
                switch self {
                case .improving: return "📈"
                case .maintaining: return "➡️"
                case .declining: return "📉"
                case .peaking: return "⭐️"
                case .recovering: return "🔄"
                }
            }
            
            var color: Color {
                switch self {
                case .improving: return .green
                case .maintaining: return .blue
                case .declining: return .orange
                case .peaking: return .purple
                case .recovering: return .yellow
                }
            }
        }
        
        enum Confidence {
            case high      // 14+ days of quality data
            case medium    // 7-13 days of data
            case low       // <7 days or missing key metrics
            
            var description: String {
                switch self {
                case .high: return "High confidence"
                case .medium: return "Medium confidence"
                case .low: return "Building baseline"
                }
            }
        }
    }
    
    /// Why you got this score - transparent breakdown
    struct ScoreBreakdown {
        let recoveryScore: Int        // 0-40 points (HRV, RHR, sleep)
        let fitnessScore: Int         // 0-30 points (recent training quality)
        let fatigueScore: Int         // 0-30 points (training load vs capacity)
        
        let recoveryDetails: String
        let fitnessDetails: String
        let fatigueDetails: String
    }
    
    // MARK: - Advanced Metrics
    
    /// Identifies performance sweet spots based on YOUR data
    struct PerformanceWindow {
        let metric: String            // e.g., "Cycling Power"
        let optimalDaysAfter: ClosedRange<Int>  // e.g., 2-3 days after strength
        let trigger: String           // What needs to happen first
        let confidence: Double        // How strong is this pattern
        let sampleSize: Int
        let averageBoost: Double      // % improvement in this window
        
        var description: String {
            let days = optimalDaysAfter.lowerBound == optimalDaysAfter.upperBound
                ? "\(optimalDaysAfter.lowerBound) days"
                : "\(optimalDaysAfter.lowerBound)-\(optimalDaysAfter.upperBound) days"
            
            return "Best \(metric) performances happen \(days) after \(trigger) (+\(String(format: "%.0f", averageBoost))% avg)"
        }
    }
    
    /// Real-time form indicator
    struct FormIndicator {
        let status: FormStatus
        let daysInStatus: Int
        let optimalActionWindow: String  // "Next 2-4 days ideal for quality work"
        let riskLevel: RiskLevel
        
        enum FormStatus {
            case fresh              // Ready for breakthrough
            case primed             // Peak performance window
            case functional         // Normal training capacity
            case fatigued          // Need recovery emphasis
            case depleted          // Rest required
            
            var label: String {
                switch self {
                case .fresh: return "Fresh"
                case .primed: return "Primed"
                case .functional: return "Functional"
                case .fatigued: return "Fatigued"
                case .depleted: return "Depleted"
                }
            }
            
            var emoji: String {
                switch self {
                case .fresh: return "💪"
                case .primed: return "🚀"
                case .functional: return "✅"
                case .fatigued: return "⚠️"
                case .depleted: return "🛑"
                }
            }
        }
        
        enum RiskLevel {
            case low
            case moderate
            case high
            case veryHigh
        }
    }
    
    // MARK: - Main Analysis Function
    
    func analyzeReadiness(
        restingHR: [HealthDataPoint],
        hrv: [HealthDataPoint],
        sleep: [HealthDataPoint],
        workouts: [WorkoutData],
        stravaActivities: [StravaActivity],
        nutrition: [DailyNutrition]
    ) -> ReadinessScore? {
        
        print("🎯 Analyzing Readiness...")
        
        // Need minimum data
        guard !restingHR.isEmpty || !hrv.isEmpty,
              !sleep.isEmpty else {
            print("   ⚠️ Insufficient data for readiness analysis")
            return nil
        }
        
        // Calculate each component
        let recovery = calculateRecoveryScore(rhr: restingHR, hrv: hrv, sleep: sleep)
        let fitness = calculateFitnessScore(workouts: workouts, activities: stravaActivities)
        let fatigue = calculateFatigueScore(
            workouts: workouts,
            activities: stravaActivities,
            recovery: recovery
        )
        
        // Combine into overall score
        let totalScore = recovery.score + fitness.score + fatigue.score
        
        // Determine trend
        let trend = determineTrend(
            recoveryHistory: restingHR + hrv,
            workloadHistory: workouts + stravaActivities.compactMap { activity in
                WorkoutData(from: activity)
            },
            currentScore: totalScore
        )
        
        // Generate recommendation
        let recommendation = generateRecommendation(
            score: totalScore,
            trend: trend,
            recovery: recovery,
            fatigue: fatigue
        )
        
        // Calculate confidence
        let confidence = determineConfidence(
            rhrDays: restingHR.count,
            hrvDays: hrv.count,
            sleepDays: sleep.count,
            workoutDays: workouts.count + stravaActivities.count
        )
        
        // Create breakdown
        let breakdown = ScoreBreakdown(
            recoveryScore: recovery.score,
            fitnessScore: fitness.score,
            fatigueScore: fatigue.score,
            recoveryDetails: recovery.details,
            fitnessDetails: fitness.details,
            fatigueDetails: fatigue.details
        )
        
        // Generate trajectory
        let trajectory = generateTrajectory(
            currentScore: totalScore,
            trend: trend,
            workoutHistory: workouts + stravaActivities.compactMap { WorkoutData(from: $0) }
        )
        
        print("   ✅ Readiness Score: \(totalScore)/100")
        print("   📊 Breakdown: Recovery \(recovery.score), Fitness \(fitness.score), Fatigue \(fatigue.score)")
        print("   \(trend.emoji) Trend: \(trend)")
        
        return ReadinessScore(
            score: totalScore,
            trend: trend,
            recommendation: recommendation,
            confidence: confidence,
            breakdown: breakdown,
            trajectory: trajectory
        )
    }
    
    // MARK: - Component Calculators
    
    private func calculateRecoveryScore(
        rhr: [HealthDataPoint],
        hrv: [HealthDataPoint],
        sleep: [HealthDataPoint]
    ) -> (score: Int, details: String) {
        
        var score = 0
        var factors: [String] = []
        
        // HRV Analysis (0-15 points)
        if !hrv.isEmpty {
            let recent7Days = Array(hrv.suffix(7))
            // Baseline should be the 28 days BEFORE the recent 7 days, not the oldest data
            let baselineStart = max(0, hrv.count - 35)
            let baselineEnd = max(0, hrv.count - 7)
            let baseline28Days = Array(hrv[baselineStart..<baselineEnd])
            
            let recentAvg = recent7Days.map(\.value).reduce(0, +) / Double(recent7Days.count)
            let baselineAvg = baseline28Days.isEmpty ? recentAvg : baseline28Days.map(\.value).reduce(0, +) / Double(baseline28Days.count)
            
            let hrvChange = ((recentAvg - baselineAvg) / baselineAvg) * 100
            
            if hrvChange >= 5 {
                score += 15
                factors.append("HRV elevated +\(Int(hrvChange))% (excellent recovery)")
            } else if hrvChange >= 0 {
                score += 12
                factors.append("HRV stable (good recovery)")
            } else if hrvChange >= -5 {
                score += 8
                factors.append("HRV slightly down (monitoring)")
            } else {
                score += 3
                factors.append("HRV suppressed (poor recovery)")
            }
        }
        
        // RHR Analysis (0-15 points)
        if !rhr.isEmpty {
            let recent7Days = Array(rhr.suffix(7))
            // Baseline should be the 28 days BEFORE the recent 7 days, not the oldest data
            let baselineStart = max(0, rhr.count - 35)
            let baselineEnd = max(0, rhr.count - 7)
            let baseline28Days = Array(rhr[baselineStart..<baselineEnd])
            
            let recentAvg = recent7Days.map(\.value).reduce(0, +) / Double(recent7Days.count)
            let baselineAvg = baseline28Days.isEmpty ? recentAvg : baseline28Days.map(\.value).reduce(0, +) / Double(baseline28Days.count)
            
            let rhrChange = recentAvg - baselineAvg
            
            if rhrChange <= -2 {
                score += 15
                factors.append("RHR down \(Int(abs(rhrChange)))bpm (excellent)")
            } else if rhrChange <= 0 {
                score += 12
                factors.append("RHR stable (good)")
            } else if rhrChange <= 3 {
                score += 7
                factors.append("RHR up \(Int(rhrChange))bpm (watch)")
            } else {
                score += 2
                factors.append("RHR elevated +\(Int(rhrChange))bpm (poor)")
            }
        }
        
        // Sleep Analysis (0-10 points)
        if !sleep.isEmpty {
            let recent7Days = Array(sleep.suffix(7))
            let avgSleep = recent7Days.map(\.value).reduce(0, +) / Double(recent7Days.count)
            
            if avgSleep >= 8.0 {
                score += 10
                factors.append("Sleep excellent (\(String(format: "%.1f", avgSleep))h)")
            } else if avgSleep >= 7.0 {
                score += 7
                factors.append("Sleep adequate (\(String(format: "%.1f", avgSleep))h)")
            } else if avgSleep >= 6.0 {
                score += 4
                factors.append("Sleep suboptimal (\(String(format: "%.1f", avgSleep))h)")
            } else {
                score += 1
                factors.append("Sleep insufficient (\(String(format: "%.1f", avgSleep))h)")
            }
        }
        
        let details = factors.joined(separator: " • ")
        return (min(score, 40), details)
    }
    
    private func calculateFitnessScore(
        workouts: [WorkoutData],
        activities: [StravaActivity]
    ) -> (score: Int, details: String) {
        
        var score = 0
        var factors: [String] = []
        
        // Recent training quality (last 14 days)
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let recentWorkouts = workouts.filter { $0.startDate >= twoWeeksAgo }
        let recentActivities = activities.filter {
            ($0.startDateFormatted ?? Date.distantPast) >= twoWeeksAgo
        }
        
        let totalWorkouts = recentWorkouts.count + recentActivities.count
        let totalDuration = recentWorkouts.reduce(0.0) { $0 + $1.duration } +
                          recentActivities.reduce(0.0) { $0 + Double($1.movingTime) }
        
        let avgDurationPerWorkout = totalWorkouts > 0 ? totalDuration / Double(totalWorkouts) : 0
        
        // Consistency score (0-15 points)
        if totalWorkouts >= 8 {
            score += 15
            factors.append("\(totalWorkouts) sessions in 14 days (excellent consistency)")
        } else if totalWorkouts >= 5 {
            score += 12
            factors.append("\(totalWorkouts) sessions in 14 days (good)")
        } else if totalWorkouts >= 3 {
            score += 8
            factors.append("\(totalWorkouts) sessions in 14 days (moderate)")
        } else {
            score += 4
            factors.append("\(totalWorkouts) sessions in 14 days (building)")
        }
        
        // Quality score based on duration (0-15 points)
        if avgDurationPerWorkout >= 3600 { // 60+ minutes
            score += 15
            factors.append("Quality volume maintained")
        } else if avgDurationPerWorkout >= 2400 { // 40+ minutes
            score += 12
            factors.append("Good training volume")
        } else if avgDurationPerWorkout >= 1800 { // 30+ minutes
            score += 8
            factors.append("Moderate volume")
        } else if avgDurationPerWorkout > 0 {
            score += 5
            factors.append("Building volume")
        }
        
        let details = factors.joined(separator: " • ")
        return (min(score, 30), details)
    }
    
    private func calculateFatigueScore(
        workouts: [WorkoutData],
        activities: [StravaActivity],
        recovery: (score: Int, details: String)
    ) -> (score: Int, details: String) {
        
        var score = 30 // Start at max, subtract for fatigue
        var factors: [String] = []
        
        // Calculate acute vs chronic load
        let calculator = TrainingLoadCalculator()
        if let loadSummary = calculator.calculateTrainingLoad(
            healthKitWorkouts: workouts,
            stravaActivities: activities,
            stepData: []
        ) {
            let acr = loadSummary.acuteChronicRatio
            
            // Optimal ACR is 0.8-1.3
            if acr < 0.8 {
                // Very fresh - minimal fatigue
                score -= 0
                factors.append("Training load low (fresh)")
            } else if acr <= 1.0 {
                // Optimal zone
                score -= 3
                factors.append("Training load optimal")
            } else if acr <= 1.3 {
                // Upper optimal
                score -= 7
                factors.append("Training load building")
            } else if acr <= 1.5 {
                // Moderate fatigue
                score -= 15
                factors.append("Elevated fatigue (ACR: \(String(format: "%.2f", acr)))")
            } else {
                // High fatigue
                score -= 25
                factors.append("High fatigue risk (ACR: \(String(format: "%.2f", acr)))")
            }
        }
        
        // Adjust based on recovery quality
        if recovery.score < 20 {
            score -= 5
            factors.append("Recovery not keeping pace")
        } else if recovery.score >= 35 {
            score += 5
            factors.append("Strong recovery response")
        }
        
        let details = factors.joined(separator: " • ")
        return (max(0, min(score, 30)), details)
    }
    
    private func determineTrend(
        recoveryHistory: [HealthDataPoint],
        workloadHistory: [WorkoutData],
        currentScore: Int
    ) -> ReadinessScore.Trend {
        
        // Compare last 3 days to previous 4 days
        guard recoveryHistory.count >= 7 else {
            return .maintaining
        }
        
        let recent3 = Array(recoveryHistory.suffix(3))
        let previous4 = Array(recoveryHistory.dropLast(3).suffix(4))
        
        let recentAvg = recent3.map(\.value).reduce(0, +) / Double(recent3.count)
        let previousAvg = previous4.map(\.value).reduce(0, +) / Double(previous4.count)
        
        let change = ((recentAvg - previousAvg) / previousAvg) * 100
        
        // Check recent workload
        let recentWorkload = workloadHistory.filter {
            $0.startDate >= Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        }
        
        // Peak detection: high score + improving + recent hard work
        if currentScore >= 75 && change > 3 && !recentWorkload.isEmpty {
            return .peaking
        }
        
        // Recovery phase: low recent workload + improving metrics
        if recentWorkload.isEmpty && change > 2 {
            return .recovering
        }
        
        // Trend based on metric change
        if change > 5 {
            return .improving
        } else if change < -5 {
            return .declining
        } else {
            return .maintaining
        }
    }
    
    private func generateRecommendation(
        score: Int,
        trend: ReadinessScore.Trend,
        recovery: (score: Int, details: String),
        fatigue: (score: Int, details: String)
    ) -> String {
        
        // Tier 1: Critical situations
        if score < 40 && recovery.score < 15 {
            return "🛑 RECOVERY NEEDED: Your body needs rest. Take a complete rest day or very light active recovery only."
        }
        
        if score < 50 && fatigue.score < 10 {
            return "⚠️ HIGH FATIGUE: Limit to easy aerobic work today. Hard sessions will dig a deeper hole."
        }
        
        // Tier 2: Peak performance windows
        if score >= 80 && trend == .peaking {
            return "🚀 PRIME WINDOW: You're primed for a breakthrough session. Go after that PR or race hard!"
        }
        
        if score >= 75 && recovery.score >= 30 {
            return "💪 READY FOR QUALITY: Great day for intervals, tempo, or other high-quality work."
        }
        
        // Tier 3: Standard guidance
        if score >= 65 {
            return "✅ GOOD TO GO: Normal training can proceed. Listen to your body on intensity."
        }
        
        if score >= 55 {
            return "🔄 MODERATE DAY: Stick to moderate efforts. Save hard work for when you're fresher."
        }
        
        if score >= 45 {
            return "😴 EASY DAY: Focus on easy aerobic work and recovery. Your body is still adapting."
        }
        
        return "🧘 REST OR RECOVERY: Prioritize recovery activities. Let your body catch up."
    }
    
    private func determineConfidence(
        rhrDays: Int,
        hrvDays: Int,
        sleepDays: Int,
        workoutDays: Int
    ) -> ReadinessScore.Confidence {
        
        let totalDays = max(rhrDays, hrvDays, sleepDays, workoutDays)
        let metricCoverage = [rhrDays > 0, hrvDays > 0, sleepDays > 0, workoutDays > 0].filter { $0 }.count
        
        if totalDays >= 14 && metricCoverage >= 3 {
            return .high
        } else if totalDays >= 7 && metricCoverage >= 2 {
            return .medium
        } else {
            return .low
        }
    }
    
    private func generateTrajectory(
        currentScore: Int,
        trend: ReadinessScore.Trend,
        workoutHistory: [WorkoutData]
    ) -> [ReadinessAnalyzer.TrajectoryPoint] {
        
        var trajectory: [ReadinessAnalyzer.TrajectoryPoint] = []
        let calendar = Calendar.current
        
        // Simple 7-day forecast
        for dayOffset in 1...7 {
            guard let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else {
                continue
            }
            
            // Simplified prediction logic
            let baselineChange: Int
            switch trend {
            case .improving:
                baselineChange = dayOffset * 2
            case .maintaining:
                baselineChange = 0
            case .declining:
                baselineChange = -dayOffset * 2
            case .peaking:
                baselineChange = dayOffset > 3 ? -dayOffset : dayOffset
            case .recovering:
                baselineChange = dayOffset * 3
            }
            
            let predictedReadiness = max(0, min(100, currentScore + baselineChange))
            let confidence = 1.0 - (Double(dayOffset) * 0.1) // Decreases with distance
            
            trajectory.append(ReadinessAnalyzer.TrajectoryPoint(
                date: futureDate,
                predictedReadiness: predictedReadiness,
                confidence: confidence,
                scenario: .planned
            ))
        }
        
        return trajectory
    }
}

// MARK: - Helper Extensions

extension WorkoutData {
    /// Convert Strava activity to WorkoutData for unified analysis
    init?(from activity: StravaActivity) {
        guard let startDate = activity.startDateFormatted else {
            return nil
        }
        
        let workoutType: HKWorkoutActivityType
        switch activity.type {
        case "Run":
            workoutType = .running
        case "Ride", "VirtualRide":
            workoutType = .cycling
        case "Swim":
            workoutType = .swimming
        case "Walk":
            workoutType = .walking
        case "Hike":
            workoutType = .hiking
        default:
            workoutType = .other
        }
        
        self.init(
            workoutType: workoutType,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(TimeInterval(activity.movingTime)),
            duration: TimeInterval(activity.movingTime),
            totalEnergyBurned: nil,
            totalDistance: activity.distance,
            averagePower: activity.averageWatts,
            averageHeartRate: activity.averageHeartrate,
            source: .strava
        )
    }
}
