//
//  DashboardViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var restingHeartRateData: [HealthDataPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hrvData: [HealthDataPoint] = []
    @Published var sleepData: [HealthDataPoint] = []
    @Published var stepCountData: [HealthDataPoint] = []
    @Published var workouts: [WorkoutData] = []
    
    private let healthKitManager = HealthKitManager.shared
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        // Get last 7 days
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        
        do {
            // Fetch all data concurrently
            async let restingHR = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrv = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleep = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let steps = healthKitManager.fetchStepCount(startDate: startDate, endDate: endDate)
            async let workoutsData = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            
            self.restingHeartRateData = try await restingHR
            self.hrvData = try await hrv
            self.sleepData = try await sleep
            self.stepCountData = try await steps
            self.workouts = try await workoutsData
            
        } catch {
            self.errorMessage = "Failed to load health data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
