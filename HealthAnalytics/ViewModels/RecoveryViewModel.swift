//
//  RecoveryViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/28/26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class RecoveryViewModel: ObservableObject {
    @Published var recoveryData: [DailyRecoveryData] = []
    @Published var selectedPeriod: TimePeriod = .month
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    private let trainingLoadCalculator = TrainingLoadCalculator()
    
    // Weights for readiness calculation
    private let hrvWeight = 0.40      // 40% - most important
    private let rhrWeight = 0.30      // 30% - second most important
    private let loadWeight = 0.20     // 20% - training load impact
    private let sleepWeight = 0.10    // 10% - sleep quality
    
    func loadRecoveryData() async {
        isLoading = true
        errorMessage = nil
        
        let endDate = Date()
        let startDate = selectedPeriod.startDate(from: endDate)
        
        do {
            // Fetch all required data
            async let rhrData = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrvData = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleepData = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let stepData = healthKitManager.fetchStepCount(startDate: startDate, endDate: endDate)
            async let hkWorkouts = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            
            // Fetch Strava activities
            let stravaActivities = try await stravaManager.fetchActivities(page: 1, perPage: 100)
            let recentActivities = stravaActivities.filter { activity in
                guard let date = activity.startDateFormatted else { return false }
                return date >= startDate && date <= endDate
            }
            
            let rhr = try await rhrData
            let hrv = try await hrvData
            let sleep = try await sleepData
            let steps = try await stepData
            let workouts = try await hkWorkouts
            
            // Calculate training load for each day
            let trainingLoadSummary = trainingLoadCalculator.calculateTrainingLoad(
                healthKitWorkouts: workouts,
                stravaActivities: recentActivities,
                stepData: steps
            )
            
            // Generate daily recovery data
            self.recoveryData = generateDailyRecoveryData(
                rhr: rhr,
                hrv: hrv,
                sleep: sleep,
                workouts: workouts,
                stravaActivities: recentActivities,
                trainingLoad: trainingLoadSummary
            )
            
        } catch {
            self.errorMessage = "Failed to load recovery data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func generateDailyRecoveryData(
        rhr: [HealthDataPoint],
        hrv: [HealthDataPoint],
        sleep: [HealthDataPoint],
        workouts: [WorkoutData],
        stravaActivities: [StravaActivity],
        trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?
    ) -> [DailyRecoveryData] {
        
        let calendar = Calendar.current
        var dailyData: [Date: DailyRecoveryData] = [:]
        
        // Calculate baselines for normalization
        let rhrBaseline = rhr.isEmpty ? 60.0 : rhr.map { $0.value }.reduce(0, +) / Double(rhr.count)
        let hrvBaseline = hrv.isEmpty ? 50.0 : hrv.map { $0.value }.reduce(0, +) / Double(hrv.count)
        
        // Populate data for each day
        for point in rhr {
            let day = calendar.startOfDay(for: point.date)
            if dailyData[day] == nil {
                dailyData[day] = DailyRecoveryData(date: day)
            }
            dailyData[day]?.restingHR = point.value
        }
        
        for point in hrv {
            let day = calendar.startOfDay(for: point.date)
            if dailyData[day] == nil {
                dailyData[day] = DailyRecoveryData(date: day)
            }
            dailyData[day]?.hrv = point.value
        }
        
        for point in sleep {
            let day = calendar.startOfDay(for: point.date)
            if dailyData[day] == nil {
                dailyData[day] = DailyRecoveryData(date: day)
            }
            dailyData[day]?.sleepHours = point.value
        }
        
        // Add training load for today
        if let load = trainingLoad {
            let today = calendar.startOfDay(for: Date())
            if dailyData[today] == nil {
                dailyData[today] = DailyRecoveryData(date: today)
            }
            dailyData[today]?.trainingLoad = load.acuteChronicRatio
        }
        
        // Calculate readiness scores
        var dataArray = Array(dailyData.values).sorted { $0.date < $1.date }
        
        for i in 0..<dataArray.count {
            let readiness = calculateReadinessScore(
                rhr: dataArray[i].restingHR,
                hrv: dataArray[i].hrv,
                sleep: dataArray[i].sleepHours,
                trainingLoad: dataArray[i].trainingLoad,
                rhrBaseline: rhrBaseline,
                hrvBaseline: hrvBaseline
            )
            
            dataArray[i].readinessScore = readiness.score
            dataArray[i].readinessLevel = readiness.level
        }
        
        return dataArray
    }
    
    private func calculateReadinessScore(
        rhr: Double?,
        hrv: Double?,
        sleep: Double?,
        trainingLoad: Double?,
        rhrBaseline: Double,
        hrvBaseline: Double
    ) -> (score: Double, level: ReadinessLevel) {
        
        var totalScore: Double = 0
        var totalWeight: Double = 0
        
        // HRV Score (40%) - Higher is better
        if let hrvValue = hrv, hrvBaseline > 0 {
            let hrvPercent = (hrvValue / hrvBaseline)
            let hrvScore = min(max(hrvPercent * 100, 0), 100)
            totalScore += hrvScore * hrvWeight
            totalWeight += hrvWeight
        }
        
        // RHR Score (30%) - Lower is better
        if let rhrValue = rhr, rhrBaseline > 0 {
            let rhrPercent = (rhrBaseline / rhrValue) // Inverted so lower RHR = higher score
            let rhrScore = min(max(rhrPercent * 100, 0), 100)
            totalScore += rhrScore * rhrWeight
            totalWeight += rhrWeight
        }
        
        // Training Load Score (20%) - ACR between 0.8-1.3 is optimal
        if let acr = trainingLoad {
            var loadScore: Double
            if acr < 0.8 {
                loadScore = 70 + (acr / 0.8) * 30 // 70-100 for fresh
            } else if acr <= 1.3 {
                loadScore = 100 // Optimal range
            } else if acr <= 1.5 {
                loadScore = 100 - ((acr - 1.3) / 0.2) * 30 // 70-100 for fatigued
            } else {
                loadScore = max(40, 70 - ((acr - 1.5) * 30)) // <70 for overreaching
            }
            totalScore += loadScore * loadWeight
            totalWeight += loadWeight
        }
        
        // Sleep Score (10%) - 7-9 hours is optimal
        if let sleepValue = sleep {
            var sleepScore: Double
            if sleepValue >= 7 && sleepValue <= 9 {
                sleepScore = 100
            } else if sleepValue >= 6 && sleepValue < 7 {
                sleepScore = 80
            } else if sleepValue > 9 && sleepValue <= 10 {
                sleepScore = 80
            } else if sleepValue >= 5 && sleepValue < 6 {
                sleepScore = 60
            } else {
                sleepScore = 40
            }
            totalScore += sleepScore * sleepWeight
            totalWeight += sleepWeight
        }
        
        // Normalize score
        let finalScore = totalWeight > 0 ? totalScore / totalWeight : 50
        
        // Determine level
        let level: ReadinessLevel
        if finalScore >= 85 {
            level = .excellent
        } else if finalScore >= 70 {
            level = .good
        } else if finalScore >= 55 {
            level = .moderate
        } else {
            level = .poor
        }
        
        return (finalScore, level)
    }
}

// MARK: - Models

struct DailyRecoveryData: Identifiable {
    let id = UUID()
    var date: Date
    var restingHR: Double?
    var hrv: Double?
    var sleepHours: Double?
    var trainingLoad: Double?
    var readinessScore: Double?
    var readinessLevel: ReadinessLevel?
    
    var hasData: Bool {
        restingHR != nil || hrv != nil || sleepHours != nil
    }
}

enum ReadinessLevel: String {
    case excellent = "Excellent"
    case good = "Good"
    case moderate = "Moderate"
    case poor = "Poor"
    
    var emoji: String {
        switch self {
        case .excellent: return "🚀"
        case .good: return "✅"
        case .moderate: return "⚠️"
        case .poor: return "🔴"
        }
    }
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .moderate: return .orange
        case .poor: return .red
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Peak condition - great for hard training"
        case .good: return "Well recovered - ready for quality work"
        case .moderate: return "Moderate recovery - easy to moderate training"
        case .poor: return "Low recovery - rest or very easy activity recommended"
        }
    }
}
