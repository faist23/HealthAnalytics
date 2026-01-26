//
//  InsightsViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import Combine

@MainActor
class InsightsViewModel: ObservableObject {
    @Published var sleepPerformanceInsight: CorrelationEngine.SleepPerformanceInsight?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var activityTypeInsights: [CorrelationEngine.ActivityTypeInsight] = []
    @Published var dataSummary: [(activityType: String, goodSleep: Int, poorSleep: Int)] = []
    @Published var simpleInsights: [CorrelationEngine.SimpleInsight] = []

    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    private let correlationEngine = CorrelationEngine()
    
    func analyzeData() async {
        isLoading = true
        errorMessage = nil
        
        // Get last 30 days for better correlation analysis
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) ?? endDate
        
        do {
            // Fetch HealthKit data
            async let sleepData = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let healthKitWorkouts = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            
            // Fetch Strava activities
            let activities = try await stravaManager.fetchActivities(page: 1, perPage: 100)
            
            // Filter to last 30 days
            let recentActivities = activities.filter { activity in
                guard let date = activity.startDateFormatted else { return false }
                return date >= startDate && date <= endDate
            }
            
            // Wait for all HealthKit data
            let sleep = try await sleepData
            let hkWorkouts = try await healthKitWorkouts
            
            // Fetch additional metrics for simple insights
            async let restingHR = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrv = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            
            let rhrData = try await restingHR
            let hrvData = try await hrv
            
            // Generate simple insights (always available)
            self.simpleInsights = correlationEngine.generateSimpleInsights(
                sleepData: sleep,
                healthKitWorkouts: hkWorkouts,
                stravaActivities: recentActivities,
                restingHRData: rhrData,
                hrvData: hrvData
            )

            // Run activity-specific analysis (better than combined)
            self.activityTypeInsights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
                sleepData: sleep,
                healthKitWorkouts: hkWorkouts,
                stravaActivities: recentActivities
            )
            
            // Get data summary for progress display
            self.dataSummary = correlationEngine.getDataSummary(
                sleepData: sleep,
                healthKitWorkouts: hkWorkouts,
                stravaActivities: recentActivities
            )

            print("📊 Analysis complete:")
            print("   Sleep data points: \(sleep.count)")
            print("   HealthKit workouts: \(hkWorkouts.count)")
            print("   Strava activities: \(recentActivities.count)")
            print("   Activity-specific insights: \(activityTypeInsights.count)")
            
        } catch {
            self.errorMessage = "Failed to analyze data: \(error.localizedDescription)"
            print("❌ Analysis error: \(error)")
        }
        
        isLoading = false
    }
}
