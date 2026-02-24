//
//  TrainingViewModel.swift
//  HealthAnalytics
//
//  ViewModel for the new Training tab
//  Handles MET analysis, training balance, and training load
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class TrainingViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MET Analysis
    @Published var metSummary: METAnalyzer.METSummary?
    
    // Training Balance
    @Published var trainingBalance: BalancedTrainingAnalyzer.TrainingBalance?
    
    // Training Load
    @Published var trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?
    
    // Raw data
    @Published var workouts: [WorkoutData] = []
    @Published var stravaActivities: [StravaActivity] = []
    @Published var stepData: [HealthDataPoint] = []
    
    var modelContainer: ModelContainer?
    
    // MARK: - Configuration
    
    func configure(container: ModelContainer) {
        self.modelContainer = container
    }
    
    // MARK: - Data Loading
    
    func loadTrainingData(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch data from SwiftData
            let dataAccess = DataAccessService(container: modelContext.container)
            
            // Get workouts and activities (last 30 days)
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            workouts = try dataAccess.fetchWorkouts(from: thirtyDaysAgo, to: Date())
            
            // Get step data (last 30 days)
            stepData = try dataAccess.fetchHealthMetrics(type: "Steps", from: thirtyDaysAgo, to: Date())
            
            // TODO: Add Strava activities when available
            stravaActivities = []
            
            // Analyze
            await analyzeTraining()
            
            isLoading = false
        } catch {
            errorMessage = "Failed to load training data: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // MARK: - Analysis
    
    private func analyzeTraining() async {
        // MET Analysis
        let metAnalyzer = METAnalyzer()
        metSummary = metAnalyzer.analyzeMETActivity(
            healthKitWorkouts: workouts,
            stravaActivities: stravaActivities,
            stepData: stepData
        )
        
        // Training Balance Analysis
        let balanceAnalyzer = BalancedTrainingAnalyzer()
        trainingBalance = balanceAnalyzer.analyzeTrainingBalance(
            healthKitWorkouts: workouts,
            stravaActivities: stravaActivities
        )
        
        // Training Load Analysis
        let loadCalculator = TrainingLoadCalculator()
        trainingLoad = loadCalculator.calculateTrainingLoad(
            healthKitWorkouts: workouts,
            stravaActivities: stravaActivities,
            stepData: stepData
        )
    }
}
