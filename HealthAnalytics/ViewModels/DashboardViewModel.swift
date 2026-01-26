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
    @Published var hrvData: [HealthDataPoint] = []
    @Published var sleepData: [HealthDataPoint] = []
    @Published var stepCountData: [HealthDataPoint] = []
    @Published var workouts: [WorkoutData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: TimePeriod = .month 
    
    private let healthKitManager = HealthKitManager.shared
    
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
