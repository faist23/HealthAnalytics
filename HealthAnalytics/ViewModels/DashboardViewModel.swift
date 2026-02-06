//
//  DashboardViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//  Updated for Local-First Architecture (SwiftData)
//

import Foundation
import Combine
import WidgetKit
import SwiftData
import SwiftUI
import HealthKit

@MainActor
class DashboardViewModel: ObservableObject {
    
    // MARK: - UI Data
    // These properties drive your charts and lists
    @Published var restingHeartRateData: [HealthDataPoint] = []
    @Published var hrvData: [HealthDataPoint] = []
    @Published var sleepData: [HealthDataPoint] = []
    @Published var stepCountData: [HealthDataPoint] = []
    @Published var workouts: [WorkoutData] = []
    
    @Published var mlPrediction: PerformancePredictor.Prediction?
    
    // Coaching Instruction
    @Published var dailyInstruction: CoachingService.DailyInstruction?
    
    // UI State
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: TimePeriod = .month
    
    // MARK: - Engines & Services
    private let coachingService = CoachingService()
    private let readinessService = PredictiveReadinessService()
    private let correlationEngine = CorrelationEngine()
    
    // MARK: - Load Data
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        // 1. Trigger Global Sync to ensure local DB is fresh
        // We await this so the dashboard updates immediately after pull
        await SyncManager.shared.performGlobalSync()
        
        print("📅 Loading Dashboard for period: \(selectedPeriod.displayName)")
        
        do {
            let context = HealthDataContainer.shared.mainContext
            let endDate = Date()
            
            // A. Analysis Window (Data needed for algorithms)
            // We need at least 60 days for Chronic Load (28d) and trends
            let analysisStartDate = Calendar.current.date(byAdding: .day, value: -60, to: endDate)!
            
            // B. Chart Window (Data selected by user)
            let chartStartDate = selectedPeriod.startDate(from: endDate)
            
            // 2. Fetch Data from SwiftData
            // We fetch the analysis window (larger set) primarily
            
            // Predicates
            let workoutPredicate = #Predicate<StoredWorkout> { $0.startDate >= analysisStartDate }
            let metricPredicate = #Predicate<StoredHealthMetric> { $0.date >= analysisStartDate }
            
            // Descriptors
            let workoutDesc = FetchDescriptor<StoredWorkout>(predicate: workoutPredicate, sortBy: [SortDescriptor(\.startDate)])
            let metricDesc = FetchDescriptor<StoredHealthMetric>(predicate: metricPredicate, sortBy: [SortDescriptor(\.date)])
            
            // Execute Fetch
            let storedWorkouts = try context.fetch(workoutDesc)
            let storedMetrics = try context.fetch(metricDesc)
            
            // 3. Map to Domain Models
            let allWorkouts = storedWorkouts.map { $0.toWorkoutData() }
            
            let allHRV = storedMetrics.filter { $0.type == "HRV" }.map { $0.toHealthDataPoint() }
            let allRHR = storedMetrics.filter { $0.type == "RHR" }.map { $0.toHealthDataPoint() }
            let allSleep = storedMetrics.filter { $0.type == "Sleep" }.map { $0.toHealthDataPoint() }
            let allSteps = storedMetrics.filter { $0.type == "Steps" }.map { $0.toHealthDataPoint() }
            
            // 4. Populate UI Properties (Filtered by Chart Window)
            self.workouts = allWorkouts.filter { $0.startDate >= chartStartDate }
            self.hrvData = allHRV.filter { $0.date >= chartStartDate }
            self.restingHeartRateData = allRHR.filter { $0.date >= chartStartDate }
            self.sleepData = allSleep.filter { $0.date >= chartStartDate }
            self.stepCountData = allSteps.filter { $0.date >= chartStartDate }
            
            // 5. Generate Coaching & Readiness (Using Full Analysis Data)
            // Note: We pass [] for stravaActivities because 'allWorkouts' already contains merged Strava data
            
            let assessment = readinessService.calculateReadiness(
                stravaActivities: [], // Empty because StoredWorkout has merged data
                healthKitWorkouts: allWorkouts
            )
            
            let insights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
                sleepData: allSleep,
                healthKitWorkouts: allWorkouts,
                stravaActivities: []
            )
            
            let recoveryStatus = correlationEngine.analyzeRecoveryStatus(
                restingHRData: allRHR,
                hrvData: allHRV
            )
            
            // 6. ML Prediction
            self.mlPrediction = PredictionCache.shared.lastPrediction
            
            // 7. Generate Final Instruction
            self.dailyInstruction = coachingService.generateDailyInstruction(
                readiness: assessment,
                insights: insights,
                recovery: recoveryStatus,
                prediction: self.mlPrediction
            )
            
            // 8. Refresh Widgets
            WidgetCenter.shared.reloadAllTimelines()
            
            print("✅ Dashboard loaded with \(self.workouts.count) workouts (Display) / \(allWorkouts.count) (Analysis)")
            
        } catch {
            self.errorMessage = "Failed to load dashboard: \(error.localizedDescription)"
            print("❌ Dashboard Load Error: \(error)")
        }
        
        isLoading = false
    }
}
