//
//  DashboardViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import Foundation
import HealthKit
import SwiftData
import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var hrvData: [HealthDataPoint] = []
    @Published var restingHeartRateData: [HealthDataPoint] = []
    @Published var sleepData: [HealthDataPoint] = []
    @Published var stepCountData: [HealthDataPoint] = []
    @Published var workouts: [WorkoutData] = []
    @Published var weightData: [HealthDataPoint] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: TimePeriod = .month
    @Published var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var endDate = Date()
    
    // Readiness data
    @Published var readinessScore: Int = 0
    @Published var readinessLevel: ReadinessLevel = .moderate
    @Published var readinessRecommendation: String = ""
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        let context = HealthDataContainer.shared.mainContext
        let rangeStart = self.startDate
        let rangeEnd = self.endDate
        
        do {
            // 2. Fetch Workouts (Filtered by Date)
            let workoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= rangeStart && $0.startDate <= rangeEnd },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
            let storedWorkouts = try context.fetch(workoutDescriptor)
            
            self.workouts = storedWorkouts.map { stored in
                WorkoutData(
                    id: UUID(uuidString: stored.id) ?? UUID(),
                    title: stored.title,
                    workoutType: stored.workoutType,
                    startDate: stored.startDate,
                    endDate: stored.startDate.addingTimeInterval(stored.duration),
                    duration: stored.duration,
                    totalEnergyBurned: stored.totalEnergyBurned,
                    totalDistance: stored.distance,
                    averagePower: stored.averagePower,
                    averageHeartRate: stored.averageHeartRate,
                    source: stored.source == "Strava" ? .strava : .appleWatch
                )
            }
            
            // 3. Fetch Health Metrics (Filtered by Date)
            let metricDescriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.date >= rangeStart && $0.date <= rangeEnd },
                sortBy: [SortDescriptor(\.date)]
            )
            let storedMetrics = try context.fetch(metricDescriptor)
            
            // Map the flat list of metrics into specific arrays for the charts
            self.hrvData = storedMetrics
                .filter { $0.type == "HRV" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "ms", dataType: .heartRateVariabilitySDNN) }
            
            self.restingHeartRateData = storedMetrics
                .filter { $0.type == "RHR" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "bpm", dataType: .restingHeartRate) }
            
            self.sleepData = storedMetrics
                .filter { $0.type == "Sleep" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "hr") }
            
            self.stepCountData = storedMetrics
                .filter { $0.type == "Steps" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "steps", dataType: .stepCount) }
            
            self.weightData = storedMetrics
                .filter { $0.type == "Weight" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "lbs", dataType: .bodyMass) }
            
            // Calculate readiness score
            calculateReadiness()
            
        } catch {
            print("Failed to fetch dashboard data: \(error)")
            self.errorMessage = "Could not load data from database."
        }
        
        isLoading = false
    }
    
    private func calculateReadiness() {
        // Readiness should ALWAYS use recent data (last 30 days), not the selected date range
        let context = HealthDataContainer.shared.mainContext
        let calendar = Calendar.current
        let now = Date()
        let readinessStart = calendar.date(byAdding: .day, value: -30, to: now)!
        
        do {
            // Fetch recent metrics for readiness calculation (last 30 days)
            let metricDescriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.date >= readinessStart && $0.date <= now },
                sortBy: [SortDescriptor(\.date)]
            )
            let recentMetrics = try context.fetch(metricDescriptor)
            
            let recentHRV = recentMetrics
                .filter { $0.type == "HRV" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "ms", dataType: .heartRateVariabilitySDNN) }
            
            let recentRHR = recentMetrics
                .filter { $0.type == "RHR" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "bpm", dataType: .restingHeartRate) }
            
            let recentSleep = recentMetrics
                .filter { $0.type == "Sleep" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "hr") }
            
            // Fetch recent workouts for readiness
            let workoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= readinessStart && $0.startDate <= now },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
            let recentStoredWorkouts = try context.fetch(workoutDescriptor)
            let recentWorkouts = recentStoredWorkouts.map { stored in
                WorkoutData(
                    id: UUID(uuidString: stored.id) ?? UUID(),
                    title: stored.title,
                    workoutType: stored.workoutType,
                    startDate: stored.startDate,
                    endDate: stored.startDate.addingTimeInterval(stored.duration),
                    duration: stored.duration,
                    totalEnergyBurned: stored.totalEnergyBurned,
                    totalDistance: stored.distance,
                    averagePower: stored.averagePower,
                    averageHeartRate: stored.averageHeartRate,
                    source: stored.source == "Strava" ? .strava : .appleWatch
                )
            }
            
            let analyzer = ReadinessAnalyzer()
            guard let readiness = analyzer.analyzeReadiness(
                restingHR: recentRHR,
                hrv: recentHRV,
                sleep: recentSleep,
                workouts: recentWorkouts,
                stravaActivities: [],
                nutrition: []
            ) else {
                readinessScore = 50
                readinessLevel = .moderate
                readinessRecommendation = "Insufficient data for readiness calculation"
                return
            }
            
            readinessScore = Int(readiness.score)
            
            // Map score to readiness level
            if readinessScore >= 80 {
                readinessLevel = .excellent
                readinessRecommendation = "Peak condition. Great for hard training or racing."
            } else if readinessScore >= 70 {
                readinessLevel = .good
                readinessRecommendation = "Good readiness. Ready for quality training sessions."
            } else if readinessScore >= 60 {
                readinessLevel = .moderate
                readinessRecommendation = "Moderate readiness. Focus on maintenance workouts."
            } else {
                readinessLevel = .poor
                readinessRecommendation = "Managing fatigue. Easy training and prioritize recovery."
            }
        } catch {
            print("Failed to calculate readiness: \(error)")
            readinessScore = 50
            readinessLevel = .moderate
            readinessRecommendation = "Error calculating readiness"
        }
    }
}
