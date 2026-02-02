//
//  DashboardViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import Combine
import WidgetKit

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var restingHeartRateData: [HealthDataPoint] = []
    @Published var hrvData: [HealthDataPoint] = []
    @Published var sleepData: [HealthDataPoint] = []
    @Published var stepCountData: [HealthDataPoint] = []
    @Published var workouts: [WorkoutData] = []
 
    @Published var mlPrediction: PerformancePredictor.Prediction?

    // Step 2: Add the coaching instruction property
    @Published var dailyInstruction: CoachingService.DailyInstruction?
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: TimePeriod = .month
    
    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    
    // Step 2: Initialize the coaching and analysis services
    private let coachingService = CoachingService()
    private let readinessService = PredictiveReadinessService()
    private let correlationEngine = CorrelationEngine()
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        let endDate = Date()
        let startDate = selectedPeriod.startDate(from: endDate)
        
        print("📅 Loading data for period: \(selectedPeriod.displayName)")
        print("   From: \(startDate.formatted(date: .abbreviated, time: .omitted))")
        print("   To: \(endDate.formatted(date: .abbreviated, time: .omitted))")
        
        do {
            // Fetch all data concurrently
            async let restingHR = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrv = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleep = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let steps = healthKitManager.fetchStepCount(startDate: startDate, endDate: endDate)
            async let workoutsData = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            async let stravaData = stravaManager.fetchActivities()
            
            self.restingHeartRateData = try await restingHR
            self.hrvData = try await hrv
            self.sleepData = try await sleep
            self.stepCountData = try await steps
            self.workouts = try await workoutsData
            let stravaActivities = (try? await stravaData) ?? []
            
            // Step 2: Generate the instruction for the athlete
            // This transforms the raw numbers into actionable coaching
            let assessment = readinessService.calculateReadiness(
                stravaActivities: stravaActivities,
                healthKitWorkouts: self.workouts
            )
            
            let insights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
                sleepData: self.sleepData,
                healthKitWorkouts: self.workouts,
                stravaActivities: stravaActivities
            )
            
            let recoveryStatus = correlationEngine.analyzeRecoveryStatus(
                restingHRData: self.restingHeartRateData,
                hrvData: self.hrvData
            )
            
            // If you have a prediction available (e.g. from the cache or a service)
            // make sure it is assigned to the local property before being used
            self.mlPrediction = PredictionCache.shared.lastPrediction

            self.dailyInstruction = coachingService.generateDailyInstruction(
                readiness: assessment,
                insights: insights,
                recovery: recoveryStatus,
                prediction: self.mlPrediction // Now 'self.mlPrediction' is in scope
            )

            WidgetCenter.shared.reloadAllTimelines() // Notify the widget
            
        } catch {
            self.errorMessage = "Failed to load health data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
