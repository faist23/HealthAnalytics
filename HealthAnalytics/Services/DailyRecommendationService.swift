//
//  DailyRecommendationService.swift
//  HealthAnalytics
//
//  HRV-guided daily training recommendations for dedicated recreational athletes
//

import Foundation
import SwiftUI

struct DailyRecommendationService {
    
    // MARK: - Daily Recommendation Model
    
    struct DailyRecommendation {
        let status: RecommendationStatus
        let headline: String
        let guidance: String
        let targetZones: [String]
        let avoidZones: [String]
        let confidence: Confidence
        let reasoning: String
        
        enum RecommendationStatus {
            case goHard      // HRV elevated, well-rested - time for intervals
            case quality     // Good HRV, ready for tempo/threshold work
            case moderate    // Normal HRV, stick to endurance
            case easy        // Suppressed HRV, Z1/Z2 only
            case rest        // Very low HRV, rest or active recovery
            
            var emoji: String {
                switch self {
                case .goHard: return "🚀"
                case .quality: return "💪"
                case .moderate: return "✅"
                case .easy: return "😌"
                case .rest: return "🛑"
                }
            }
            
            var color: Color {
                switch self {
                case .goHard: return .purple
                case .quality: return .green
                case .moderate: return .blue
                case .easy: return .orange
                case .rest: return .red
                }
            }
        }
        
        enum Confidence {
            case high      // 14+ days of HRV data
            case medium    // 7-13 days
            case low       // <7 days
            
            var description: String {
                switch self {
                case .high: return "High confidence"
                case .medium: return "Medium confidence"
                case .low: return "Building baseline"
                }
            }
        }
    }
    
    // MARK: - HRV Analysis
    
    struct HRVStatus {
        let currentHRV: Double
        let baselineHRV: Double
        let percentChange: Double
        let trend: Trend
        
        enum Trend {
            case elevated      // +5% or more above baseline
            case normal        // Within ±5% of baseline
            case suppressed    // -5% to -15% below baseline
            case veryLow       // More than -15% below baseline
        }
    }
    
    // MARK: - Main Analysis Function
    
    func generateDailyRecommendation(
        hrvData: [HealthDataPoint],
        sleepData: [HealthDataPoint],
        rhrData: [HealthDataPoint],
        workouts: [WorkoutData],
        readinessScore: Int?
    ) -> DailyRecommendation? {
        
        print("🎯 Generating Daily Recommendation...")
        
        // Need minimum HRV data
        guard hrvData.count >= 7 else {
            print("   ⚠️ Need at least 7 days of HRV data")
            return nil
        }
        
        // Analyze HRV status
        let hrvStatus = analyzeHRVStatus(hrvData: hrvData)
        
        // Get latest sleep quality
        let recentSleep = getRecentSleep(sleepData: sleepData)
        
        // Check training load
        let trainingLoad = assessRecentTrainingLoad(workouts: workouts)
        
        // Determine confidence level
        let confidence = determineConfidence(
            hrvDays: hrvData.count,
            sleepDays: sleepData.count,
            workoutDays: workouts.count
        )
        
        // Generate recommendation based on all factors
        let recommendation = determineRecommendation(
            hrvStatus: hrvStatus,
            recentSleep: recentSleep,
            trainingLoad: trainingLoad,
            readinessScore: readinessScore,
            confidence: confidence
        )
        
        print("   ✅ Recommendation: \(recommendation.status)")
        print("   📊 HRV: \(Int(hrvStatus.currentHRV))ms (baseline: \(Int(hrvStatus.baselineHRV))ms, \(hrvStatus.percentChange > 0 ? "+" : "")\(String(format: "%.1f", hrvStatus.percentChange))%)")
        
        return recommendation
    }
    
    // MARK: - HRV Analysis
    
    private func analyzeHRVStatus(hrvData: [HealthDataPoint]) -> HRVStatus {
        // Get today's or most recent HRV
        let sortedHRV = hrvData.sorted { $0.date > $1.date }
        let currentHRV = sortedHRV.first?.value ?? 0
        
        // Calculate 7-day rolling baseline from the previous 28 days
        let baselineStart = max(0, hrvData.count - 35)
        let baselineEnd = max(0, hrvData.count - 7)
        let baselineData = Array(hrvData[baselineStart..<baselineEnd])
        
        let baselineHRV = baselineData.isEmpty ? currentHRV :
            baselineData.map(\.value).reduce(0, +) / Double(baselineData.count)
        
        // Calculate percent change
        let percentChange = ((currentHRV - baselineHRV) / baselineHRV) * 100
        
        // Determine trend
        let trend: HRVStatus.Trend
        if percentChange >= 5 {
            trend = .elevated
        } else if percentChange >= -5 {
            trend = .normal
        } else if percentChange >= -15 {
            trend = .suppressed
        } else {
            trend = .veryLow
        }
        
        return HRVStatus(
            currentHRV: currentHRV,
            baselineHRV: baselineHRV,
            percentChange: percentChange,
            trend: trend
        )
    }
    
    // MARK: - Sleep Assessment
    
    private func getRecentSleep(sleepData: [HealthDataPoint]) -> Double? {
        guard !sleepData.isEmpty else { return nil }
        
        // Get last night's sleep
        // Sleep data is stored with the wake-up day as the date
        // So for today's readiness, we want today's sleep entry (last night's sleep)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // First try to find today's sleep (most recent night)
        if let todaySleep = sleepData.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            return todaySleep.value
        }
        
        // Fallback: get the most recent sleep entry
        let sortedSleep = sleepData.sorted { $0.date > $1.date }
        return sortedSleep.first?.value
    }
    
    // MARK: - Training Load Assessment
    
    private func assessRecentTrainingLoad(workouts: [WorkoutData]) -> TrainingLoadStatus {
        let calendar = Calendar.current
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: Date())!
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        
        let last3Days = workouts.filter { $0.startDate >= threeDaysAgo }
        let last7Days = workouts.filter { $0.startDate >= sevenDaysAgo }
        
        let recent3DaysVolume = last3Days.reduce(0.0) { $0 + $1.duration }
        let recent7DaysVolume = last7Days.reduce(0.0) { $0 + $1.duration }
        
        // Check for hard sessions in last 3 days (based on duration or intensity)
        let hasRecentHardSession = last3Days.contains { workout in
            workout.duration > 3600 || // Over 1 hour
            (workout.averageHeartRate ?? 0) > 150 // High intensity
        }
        
        return TrainingLoadStatus(
            last3DaysCount: last3Days.count,
            last7DaysCount: last7Days.count,
            recent3DaysVolume: recent3DaysVolume,
            recent7DaysVolume: recent7DaysVolume,
            hasRecentHardSession: hasRecentHardSession
        )
    }
    
    struct TrainingLoadStatus {
        let last3DaysCount: Int
        let last7DaysCount: Int
        let recent3DaysVolume: Double
        let recent7DaysVolume: Double
        let hasRecentHardSession: Bool
    }
    
    // MARK: - Recommendation Logic
    
    private func determineRecommendation(
        hrvStatus: HRVStatus,
        recentSleep: Double?,
        trainingLoad: TrainingLoadStatus,
        readinessScore: Int?,
        confidence: DailyRecommendation.Confidence
    ) -> DailyRecommendation {
        
        var reasoning: [String] = []
        
        // Primary decision: HRV status
        let status: DailyRecommendation.RecommendationStatus
        let headline: String
        let guidance: String
        var targetZones: [String] = []
        var avoidZones: [String] = []
        
        switch hrvStatus.trend {
        case .elevated:
            // HRV is high - check if we're fresh enough for hard work
            if trainingLoad.hasRecentHardSession {
                // High HRV but just did hard work - quality but not breakthrough
                status = .quality
                headline = "Ready for Quality Work"
                guidance = "Your HRV is elevated, but you've done recent hard training. Good day for tempo or threshold work, but save breakthrough efforts for when you're more recovered."
                targetZones = ["Zone 3 (Tempo)", "Zone 4 (Threshold)", "Sweet Spot"]
                avoidZones = ["Zone 6+ (Max efforts)", "Long VO2 intervals"]
                reasoning.append("HRV elevated +\(String(format: "%.1f", hrvStatus.percentChange))%")
                reasoning.append("Recent hard session detected")
            } else if (recentSleep ?? 0) < 6.5 {
                // High HRV but poor sleep
                status = .moderate
                headline = "Good HRV, But Sleep Matters"
                guidance = "Your HRV looks great, but last night's sleep was suboptimal. Stick to moderate endurance work today."
                targetZones = ["Zone 2 (Endurance)", "Zone 3 (Tempo)"]
                avoidZones = ["Zone 5+ (Hard intervals)"]
                reasoning.append("HRV elevated +\(String(format: "%.1f", hrvStatus.percentChange))%")
                reasoning.append("Sleep below optimal (\(String(format: "%.1f", recentSleep ?? 0))h)")
            } else {
                // Perfect conditions for hard work
                status = .goHard
                headline = "GO HARD - Prime Window"
                guidance = "Everything is aligned: elevated HRV, good recovery, and no recent hard sessions. This is your window for breakthrough efforts, PRs, or race-pace intervals."
                targetZones = ["Zone 5 (VO2max)", "Zone 6 (Anaerobic)", "Race efforts", "PR attempts"]
                avoidZones = []
                reasoning.append("HRV elevated +\(String(format: "%.1f", hrvStatus.percentChange))%")
                reasoning.append("Well-rested, no recent hard work")
                if let sleep = recentSleep {
                    reasoning.append("Good sleep (\(String(format: "%.1f", sleep))h)")
                }
            }
            
        case .normal:
            // Normal HRV - standard training can proceed
            if trainingLoad.last3DaysCount >= 3 {
                // High frequency recently
                status = .moderate
                headline = "Active Recovery or Easy"
                guidance = "Your HRV is normal, but you've been training frequently. Consider an easy day or active recovery to consolidate adaptations."
                targetZones = ["Zone 1 (Recovery)", "Zone 2 (Easy)"]
                avoidZones = ["Zone 4+ (Hard work)"]
                reasoning.append("HRV within normal range")
                reasoning.append("\(trainingLoad.last3DaysCount) workouts in last 3 days")
            } else {
                status = .moderate
                headline = "Normal Training Day"
                guidance = "Your HRV is stable. Good day for moderate endurance work, tempo, or technique focus. Save hard intervals for when HRV is elevated."
                targetZones = ["Zone 2 (Endurance)", "Zone 3 (Tempo)", "Skills work"]
                avoidZones = ["Long VO2 sessions", "Max efforts"]
                reasoning.append("HRV stable (within ±5% of baseline)")
            }
            
        case .suppressed:
            // HRV down 5-15%
            status = .easy
            headline = "EASY - Zone 1/2 Only"
            guidance = "Your HRV is suppressed, indicating accumulated fatigue. Stick to easy aerobic work (Zone 1-2) or consider rest. Hard training now will dig a deeper hole."
            targetZones = ["Zone 1 (Recovery)", "Zone 2 (Easy base)"]
            avoidZones = ["Zone 3+", "Any intervals", "Long duration"]
            reasoning.append("HRV suppressed \(String(format: "%.1f", hrvStatus.percentChange))%")
            reasoning.append("Body needs recovery stress only")
            
        case .veryLow:
            // HRV down >15%
            status = .rest
            headline = "REST - Recovery Needed"
            guidance = "Your HRV is significantly suppressed. Take a complete rest day or very light active recovery only. Your body is telling you it needs time to adapt."
            targetZones = ["Complete rest", "Very light recovery walk/spin (<30min Zone 1)"]
            avoidZones = ["Any structured training", "All zones above Z1"]
            reasoning.append("HRV very low \(String(format: "%.1f", hrvStatus.percentChange))%")
            reasoning.append("Recovery urgently needed")
        }
        
        // Adjust based on readiness score if available
        if let score = readinessScore {
            if score < 50 && status == .moderate {
                // Readiness says rest even if HRV looks normal
                reasoning.append("Readiness score low (\(score))")
            }
        }
        
        return DailyRecommendation(
            status: status,
            headline: headline,
            guidance: guidance,
            targetZones: targetZones,
            avoidZones: avoidZones,
            confidence: confidence,
            reasoning: reasoning.joined(separator: " • ")
        )
    }
    
    // MARK: - Confidence Calculation
    
    private func determineConfidence(
        hrvDays: Int,
        sleepDays: Int,
        workoutDays: Int
    ) -> DailyRecommendation.Confidence {
        let metricCoverage = [hrvDays > 0, sleepDays > 0, workoutDays > 0].filter { $0 }.count
        
        if hrvDays >= 14 && metricCoverage >= 2 {
            return .high
        } else if hrvDays >= 7 && metricCoverage >= 2 {
            return .medium
        } else {
            return .low
        }
    }
}
