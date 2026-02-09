//
//  ReadinessViewModel.swift
//  HealthAnalytics
//
//  Created for HealthAnalytics
//

import Foundation
import Combine
import WidgetKit
import SwiftData

@MainActor
class ReadinessViewModel: ObservableObject {
    
    @Published var readinessScore: ReadinessAnalyzer.ReadinessScore?
    @Published var performanceWindows: [PerformancePatternAnalyzer.PerformanceWindow] = []
    @Published var optimalTimings: [PerformancePatternAnalyzer.OptimalTiming] = []
    @Published var workoutSequences: [PerformancePatternAnalyzer.WorkoutSequence] = []
    @Published var formIndicator: ReadinessAnalyzer.FormIndicator?
    
    // Coaching Layer
    @Published var dailyInstruction: CoachingService.DailyInstruction?
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // ML Prediction
    @Published var mlPrediction:      PerformancePredictor.Prediction?
    @Published var mlFeatureWeights:  PerformancePredictor.FeatureWeights?
    @Published var mlError:           String?
    
    private let readinessAnalyzer = ReadinessAnalyzer()
    private let patternAnalyzer = PerformancePatternAnalyzer()
    
    // Coaching dependencies
    private let coachingService = CoachingService()
    private let predictiveReadinessService = PredictiveReadinessService()
    private let correlationEngine = CorrelationEngine()
    
    func analyze() async {
        isLoading = true
        errorMessage = nil
        
        // 1. Trigger Global Sync
        await SyncManager.shared.performGlobalSync()
        
        // 2. Check if we are still backfilling to avoid database collisions
        if SyncManager.shared.isBackfillingHistory {
            print("⏳ Analysis paused: System is backfilling historical data.")
            return
        }
        
        do {
            print("📊 Fetching data from SwiftData on background thread...")
            
            // FIX: Access the container correctly.
            // If HealthDataContainer.shared IS the container, use .shared
            // If it's a wrapper, ensure this property name matches your definition.
            let container = HealthDataContainer.shared
            
            // 3. Offload FETCHING to a background task
            // We 'await' this task, which makes the 'catch' block reachable.
            let results = try await Task.detached(priority: .userInitiated) {
                let bgContext = ModelContext(container)
                
                // Perform fetches (These can throw, which satisfies the 'try')
                let storedWorkouts = try bgContext.fetch(FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.startDate)]))
                let storedMetrics = try bgContext.fetch(FetchDescriptor<StoredHealthMetric>(sortBy: [SortDescriptor(\.date)]))
                let storedNutrition = try bgContext.fetch(FetchDescriptor<StoredNutrition>(sortBy: [SortDescriptor(\.date)]))
                
                // Map raw SwiftData objects to Sendable structs
                let workouts = storedWorkouts.map { $0.toWorkoutData() }
                let nutrition = storedNutrition.map { $0.toDailyNutrition() }
                let hrv = storedMetrics.filter { $0.type == "HRV" }.map { $0.toHealthDataPoint() }
                let rhr = storedMetrics.filter { $0.type == "RHR" }.map { $0.toHealthDataPoint() }
                let sleep = storedMetrics.filter { $0.type == "Sleep" }.map { $0.toHealthDataPoint() }
                
                // ADD THESE PRINT STATEMENTS HERE
                    print("-----------------------------------------")
                    print("📈 DATABASE METRIC SUMMARY:")
                    print("   Total Workouts: \(workouts.count)")
                    print("   Sleep Samples:  \(sleep.count)")
                    print("   HRV Samples:    \(hrv.count)")
                    print("   RHR Samples:    \(rhr.count)")
                    print("   Nutrition Days: \(nutrition.count)")
                    print("-----------------------------------------")

                return (workouts, nutrition, hrv, rhr, sleep)
            }.value
            
            // 4. Update UI Properties on the Main Actor
            // (results.0 = workouts, results.1 = nutrition, results.2 = hrv, results.3 = rhr, results.4 = sleep)
            
            self.readinessScore = readinessAnalyzer.analyzeReadiness(
                restingHR: results.3, hrv: results.2, sleep: results.4,
                workouts: results.0, stravaActivities: [], nutrition: results.1
            )
            
            self.performanceWindows = patternAnalyzer.discoverPerformanceWindows(
                workouts: results.0, activities: [], sleep: results.4, nutrition: results.1
            )
            
            self.optimalTimings = patternAnalyzer.discoverOptimalTiming(workouts: results.0, activities: [])
            
            self.workoutSequences = patternAnalyzer.discoverWorkoutSequences(workouts: results.0, activities: [])
            
            if let readiness = self.readinessScore {
                self.formIndicator = generateFormIndicator(from: readiness, workouts: results.0)
            }
            
            // 5. Coaching Logic
            let assessment = predictiveReadinessService.calculateReadiness(
                stravaActivities: [],
                healthKitWorkouts: results.0
            )
            
            let insights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
                sleepData: results.4,
                healthKitWorkouts: results.0,
                stravaActivities: []
            )
            
            let recoveryStatus = correlationEngine.analyzeRecoveryStatus(
                restingHRData: results.3,
                hrvData: results.2
            )
            
            self.dailyInstruction = coachingService.generateDailyInstruction(
                readiness: assessment,
                insights: insights,
                recovery: recoveryStatus,
                prediction: mlPrediction
            )
            
            // 6. ML Prediction
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -120, to: endDate)!
            
            await trainAndPredict(
                sleep: results.4, hrv: results.2, restingHR: results.3,
                workouts: results.0, startDate: startDate, endDate: endDate,
                currentNutrition: results.1
            )
            
            isLoading = false
            
        } catch {
            print("❌ Analysis failed: \(error.localizedDescription)")
            self.errorMessage = "Analysis failed: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // MARK: - ML Prediction
    
    @MainActor
    private func trainAndPredict(
        sleep:            [HealthDataPoint],
        hrv:              [HealthDataPoint],
        restingHR:        [HealthDataPoint],
        workouts:         [WorkoutData],
        startDate:        Date,
        endDate:          Date,
        currentNutrition: [DailyNutrition]
    ) async {
        let cache = PredictionCache.shared
        
        // 1. Data Minimum Check
        guard sleep.count >= 7, hrv.count >= 7, restingHR.count >= 7 else {
            self.mlError = "Establishing baseline... (Need 7 days of heart metrics)"
            return
        }
        
        let fp = PredictionCache.fingerprint(
            workoutCount: workouts.count,
            sleepCount:   sleep.count,
            hrvCount:     hrv.count,
            rhrCount:     restingHR.count
        )
        
        // 2. Training Phase
        if !cache.isUpToDate(fingerprint: fp) {
            do {
                print("🤖 Training ML models on \(workouts.count) activities...")
                let models = try await PerformancePredictor.train(
                    sleepData:         sleep,
                    hrvData:           hrv,
                    restingHRData:     restingHR,
                    healthKitWorkouts: workouts,
                    stravaActivities:  [],
                    nutritionData:     currentNutrition,
                    readinessService:  predictiveReadinessService
                )
                
                if let instruction = self.dailyInstruction {
                    cache.store(models: models, fingerprint: fp, instruction: instruction)
                }
                print("✅ ML Models trained successfully.")
            } catch {
                print("❌ ML Training Error: \(error.localizedDescription)")
                mlError = "Training failed: \(error.localizedDescription)"
                return
            }
        }
        
        // 3. Prediction Phase
        guard let lastSleep = sleep.last?.value,
              let lastHRV   = hrv.last?.value,
              let lastRHR   = restingHR.last?.value else {
            mlError = "Incomplete metrics for today's prediction."
            return
        }
        
        let currentAssessment = predictiveReadinessService.calculateReadiness(
            stravaActivities: [],
            healthKitWorkouts: workouts
        )
        
        let currentCarbs = currentNutrition.last?.totalCarbs ?? 0
        
        // Try to predict for the athlete's primary sports
        let activityTypes = ["Ride", "Run"] // Put Ride first if you're a cyclist
        var predictionFound = false
        
        for activityType in activityTypes {
            do {
                let prediction = try PerformancePredictor.predict(
                    models:       cache.models,
                    activityType: activityType,
                    sleepHours:   lastSleep,
                    hrvMs:         lastHRV,
                    restingHR:    lastRHR,
                    acwr:         currentAssessment.acwr,
                    carbs:        currentCarbs
                )
                
                // If we successfully predict one, we show it
                self.mlPrediction     = prediction
                self.mlFeatureWeights = cache.models.first(where: { $0.activityType == activityType })?.featureWeights
                self.mlError          = nil
                cache.storePrediction(prediction)
                
                updateCoachingAndWidget(
                    prediction: prediction,
                    fp: fp,
                    sleep: sleep,
                    workouts: workouts,
                    restingHR: restingHR,
                    hrv: hrv,
                    acwr: currentAssessment.acwr,
                    carbs: currentCarbs
                )
                predictionFound = true
                break // Exit loop after first successful prediction
            } catch {
                print("ℹ️ No prediction available for \(activityType): \(error.localizedDescription)")
                continue
            }
        }
        
        if !predictionFound {
            mlError = "Not enough \(activityTypes.joined(separator: "/")) data to predict output."
        }
    }
    
    private func generateFormIndicator(
        from readiness: ReadinessAnalyzer.ReadinessScore,
        workouts: [WorkoutData]
    ) -> ReadinessAnalyzer.FormIndicator {
        let status: ReadinessAnalyzer.FormIndicator.FormStatus
        let riskLevel: ReadinessAnalyzer.FormIndicator.RiskLevel
        let optimalWindow: String
        
        if readiness.score >= 85 {
            status = .primed
            optimalWindow = "Next 1-3 days perfect for breakthrough efforts"
            riskLevel = .low
        } else if readiness.score >= 70 {
            status = .fresh
            optimalWindow = "Next 2-4 days good for quality training"
            riskLevel = .low
        } else if readiness.score >= 55 {
            status = .functional
            optimalWindow = "Maintain moderate training load"
            riskLevel = .moderate
        } else if readiness.score >= 40 {
            status = .fatigued
            optimalWindow = "Focus on recovery before hard sessions"
            riskLevel = .high
        } else {
            status = .depleted
            optimalWindow = "Rest required before resuming training"
            riskLevel = .veryHigh
        }
        
        return ReadinessAnalyzer.FormIndicator(
            status: status,
            daysInStatus: 1,
            optimalActionWindow: optimalWindow,
            riskLevel: riskLevel
        )
    }
    
    private func updateCoachingAndWidget(
        prediction: PerformancePredictor.Prediction?,
        fp: PredictionCache.DataFingerprint,
        sleep: [HealthDataPoint],
        workouts: [WorkoutData],
        restingHR: [HealthDataPoint],
        hrv: [HealthDataPoint],
        acwr: Double,
        carbs: Double
    ) {
        let assessment = predictiveReadinessService.calculateReadiness(
            stravaActivities: [],
            healthKitWorkouts: workouts
        )
        
        let insights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
            sleepData: sleep,
            healthKitWorkouts: workouts,
            stravaActivities: []
        )
        
        let recoveryStatus = correlationEngine.analyzeRecoveryStatus(
            restingHRData: restingHR,
            hrvData: hrv
        )
        
        let instruction = coachingService.generateDailyInstruction(
            readiness: assessment,
            insights: insights,
            recovery: recoveryStatus,
            prediction: prediction
        )
        
        self.dailyInstruction = instruction
        
        PredictionCache.shared.store(
            models: PredictionCache.shared.models,
            fingerprint: fp,
            instruction: instruction
        )
        
        WidgetCenter.shared.reloadAllTimelines()
    }
}
