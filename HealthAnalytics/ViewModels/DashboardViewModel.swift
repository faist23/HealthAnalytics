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
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        let context = HealthDataContainer.shared.mainContext
        let calendar = Calendar.current
        let now = Date()
        
        // 1. Calculate Date Range based on selection
        let startDate: Date
        switch selectedPeriod {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .day, value: -30, to: now)!
        case .quarter: // 🟢 Added handling for quarter
            startDate = calendar.date(byAdding: .day, value: -90, to: now)!
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -6, to: now)!
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now)!
        case .all: // 🟢 FIXED: Added .all case to make switch exhaustive
            startDate = calendar.date(byAdding: .year, value: -5, to: now)!
        }
        
        do {
            // 2. Fetch Workouts (Filtered by Date)
            let workoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= startDate && $0.startDate <= now },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
            let storedWorkouts = try context.fetch(workoutDescriptor)
            
            self.workouts = storedWorkouts.map { stored in
                WorkoutData(
                    id: UUID(uuidString: stored.id) ?? UUID(),
                    workoutType: stored.workoutType,
                    startDate: stored.startDate,
                    endDate: stored.startDate.addingTimeInterval(stored.duration),
                    duration: stored.duration,
                    totalEnergyBurned: stored.totalEnergyBurned,
                    totalDistance: stored.distance,
                    averagePower: stored.averagePower,
                    source: stored.source == "Strava" ? .strava : .appleWatch
                )
            }
            
            // 3. Fetch Health Metrics (Filtered by Date)
            let metricDescriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.date >= startDate && $0.date <= now },
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
                // 🟢 FIXED: Removed dataType argument (passed nil implicitly) because .sleepAnalysis is a Category, not a Quantity
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "hr") }
            
            self.stepCountData = storedMetrics
                .filter { $0.type == "Steps" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "steps", dataType: .stepCount) }
            
            self.weightData = storedMetrics
                .filter { $0.type == "Weight" }
                .map { HealthDataPoint(date: $0.date, value: $0.value, unit: "lbs", dataType: .bodyMass) }
            
        } catch {
            print("Failed to fetch dashboard data: \(error)")
            self.errorMessage = "Could not load data from database."
        }
        
        isLoading = false
    }
}
