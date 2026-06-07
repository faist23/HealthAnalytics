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
    @Published var intraDayReadiness: RecoveryDecayService.IntraDayReadiness?

    // Holistic metrics (Phase 1.2 — now sourced from ReadinessRepository)
    @Published var holisticMetrics: HealthMetrics?

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupReadinessSubscription()
    }

    private func setupReadinessSubscription() {
        ReadinessRepository.shared.$currentReadiness
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unified in
                guard let self = self, let unified = unified else { return }
                self.readinessScore = unified.score
                self.readinessLevel = unified.level
                self.readinessRecommendation = unified.coachAdvice
                self.intraDayReadiness = unified.intraDay
                self.holisticMetrics = unified.holisticMetrics

                // Raw chart arrays now sourced from the repo (Phase 1.2)
                self.hrvData = unified.hrvData
                self.restingHeartRateData = unified.rhrData
                self.sleepData = unified.sleepData
                self.stepCountData = unified.stepCountData
                self.workouts = unified.workouts
                self.weightData = unified.weightData
            }
            .store(in: &cancellables)
    }
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        let context = HealthDataContainer.shared.mainContext
        
        // Refresh readiness first to ensure single source of truth
        await ReadinessRepository.shared.refreshIfNecessary(modelContext: context)
        
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
            
            // The readiness score is now handled via subscription to ReadinessRepository
            
        } catch {
            #if DEBUG
            print("Failed to fetch dashboard data: \(error)")
            #endif
            self.errorMessage = "Could not load data from database."
        }
        
        isLoading = false
    }
    
    // holisticMetrics is now a @Published property, populated via the
    // ReadinessRepository subscription above (Phase 1.2 migration).
}
