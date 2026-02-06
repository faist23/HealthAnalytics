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
        // This updates SwiftData with the latest 120 days of data from HealthKit/Strava
        await SyncManager.shared.performGlobalSync()
        
        do {
            print("📊 Loading data from local storage for analysis...")
            
            // 2. Fetch from SwiftData (Single Source of Truth)
            let context = HealthDataContainer.shared.mainContext
            
            // Fetch raw persistent objects
            let storedWorkouts = try context.fetch(FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.startDate)]))
            let storedMetrics = try context.fetch(FetchDescriptor<StoredHealthMetric>(sortBy: [SortDescriptor(\.date)]))
            let storedNutrition = try context.fetch(FetchDescriptor<StoredNutrition>(sortBy: [SortDescriptor(\.date)]))
            
            // 3. Map to Domain Models using your new DomainMapping.swift extensions
            let workouts = storedWorkouts.map { $0.toWorkoutData() }
            let nutrition = storedNutrition.map { $0.toDailyNutrition() }
            
            let hrv = storedMetrics.filter { $0.type == "HRV" }.map { $0.toHealthDataPoint() }
            let rhr = storedMetrics.filter { $0.type == "RHR" }.map { $0.toHealthDataPoint() }
            let sleep = storedMetrics.filter { $0.type == "Sleep" }.map { $0.toHealthDataPoint() }
            
            print("✅ Data loaded from storage")
            print("   • Resting HR: \(rhr.count) points")
            print("   • Workouts: \(workouts.count) (HK + Strava)")
            print("   • Nutrition: \(nutrition.count) days")
            
            // 4. Analyze Readiness
            readinessScore = readinessAnalyzer.analyzeReadiness(
                restingHR: rhr,
                hrv: hrv,
                sleep: sleep,
                workouts: workouts,
                stravaActivities: [], // Empty because they are already merged into 'workouts'
                nutrition: nutrition
            )
            
            // 5. Discover Patterns
            performanceWindows = patternAnalyzer.discoverPerformanceWindows(
                workouts: workouts,
                activities: [],
                sleep: sleep,
                nutrition: nutrition
            )
            
            optimalTimings = patternAnalyzer.discoverOptimalTiming(
                workouts: workouts,
                activities: []
            )
            
            workoutSequences = patternAnalyzer.discoverWorkoutSequences(
                workouts: workouts,
                activities: []
            )
            
            // 6. Generate Form Indicator
            if let readiness = readinessScore {
                formIndicator = generateFormIndicator(from: readiness, workouts: workouts)
            }
            
            // 7. Generate Coaching Instruction
            let assessment = predictiveReadinessService.calculateReadiness(
                stravaActivities: [],
                healthKitWorkouts: workouts // Pass unified list
            )
            
            let insights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
                sleepData: sleep,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            let recoveryStatus = correlationEngine.analyzeRecoveryStatus(
                restingHRData: rhr,
                hrvData: hrv
            )
            
            self.dailyInstruction = coachingService.generateDailyInstruction(
                readiness: assessment,
                insights: insights,
                recovery: recoveryStatus,
                prediction: mlPrediction
            )
            
            isLoading = false
            
            // 8. Trigger ML Prediction
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -120, to: endDate)!
            
            await trainAndPredict(
                sleep:            sleep,
                hrv:              hrv,
                restingHR:        rhr,
                workouts:         workouts,
                startDate:        startDate,
                endDate:          endDate,
                currentNutrition: nutrition // Pass the mapped nutrition array
            )
            
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
            isLoading = false
            print("❌ Analysis error: \(error)")
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
        currentNutrition: [DailyNutrition] // This matches the call site in analyze()
    ) async {
        let cache = PredictionCache.shared
        
        let fp = PredictionCache.fingerprint(
            workoutCount: workouts.count,
            sleepCount:   sleep.count,
            hrvCount:     hrv.count,
            rhrCount:     restingHR.count
        )
        
        if !cache.isUpToDate(fingerprint: fp) {
            do {
                // Pass unified workouts and mapped nutrition
                let models = try await PerformancePredictor.train(
                    sleepData:         sleep,
                    hrvData:           hrv,
                    restingHRData:     restingHR,
                    healthKitWorkouts: workouts,
                    stravaActivities:  [], // Unified in workouts
                    nutritionData:     currentNutrition,
                    readinessService:  predictiveReadinessService
                )
                
                if let instruction = self.dailyInstruction {
                    cache.store(models: models, fingerprint: fp, instruction: instruction)
                }
            } catch {
                mlError = error.localizedDescription
                return
            }
        }
        
        guard let lastSleep = sleep.last?.value,
              let lastHRV   = hrv.last?.value,
              let lastRHR   = restingHR.last?.value else {
            mlError = "Need sleep, HRV, and resting HR data to predict"
            return
        }
        
        let currentAssessment = predictiveReadinessService.calculateReadiness(
            stravaActivities: [],
            healthKitWorkouts: workouts
        )
        
        // FIXED: Use 'currentNutrition' parameter instead of undefined 'nutrition'
        let currentCarbs = currentNutrition.last?.totalCarbs ?? 0
        
        let activityTypes = ["Run", "Ride"]
        for activityType in activityTypes {
            do {
                let prediction = try PerformancePredictor.predict(
                    models:       cache.models,
                    activityType: activityType,
                    sleepHours:   lastSleep,
                    hrvMs:        lastHRV,
                    restingHR:    lastRHR,
                    acwr:         currentAssessment.acwr,
                    carbs:        currentCarbs
                )
                
                self.mlPrediction     = prediction
                self.mlFeatureWeights = cache.models.first?.featureWeights
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
                return
            } catch { continue }
        }
        mlError = "No trained model available"
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
