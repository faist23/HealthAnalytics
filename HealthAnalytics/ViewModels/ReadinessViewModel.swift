//
//  ReadinessViewModel.swift
//  HealthAnalytics
//
//  View model for revolutionary readiness and pattern insights
//

import Foundation
import Combine

@MainActor
class ReadinessViewModel: ObservableObject {
    
    @Published var readinessScore: ReadinessAnalyzer.ReadinessScore?
    @Published var performanceWindows: [PerformancePatternAnalyzer.PerformanceWindow] = []
    @Published var optimalTimings: [PerformancePatternAnalyzer.OptimalTiming] = []
    @Published var workoutSequences: [PerformancePatternAnalyzer.WorkoutSequence] = []
    @Published var formIndicator: ReadinessAnalyzer.FormIndicator?
    
    @Published var isLoading = false
    @Published var errorMessage: String?

    // ML Prediction
    @Published var mlPrediction:      PerformancePredictor.Prediction?
    @Published var mlFeatureWeights:  PerformancePredictor.FeatureWeights?
    @Published var mlError:           String?

    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    
    private let readinessAnalyzer = ReadinessAnalyzer()
    private let patternAnalyzer = PerformancePatternAnalyzer()
    
    func analyze() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch all necessary data
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -90, to: endDate)! // 90 days
            
            print("📊 Starting Readiness Analysis...")
            
            // Fetch from HealthKit
            let restingHR = try await healthKitManager.fetchRestingHeartRate(
                startDate: startDate,
                endDate: endDate
            )
            
            let hrv = try await healthKitManager.fetchHeartRateVariability(
                startDate: startDate,
                endDate: endDate
            )
            
            let sleep = try await healthKitManager.fetchSleepDuration(
                startDate: startDate,
                endDate: endDate
            )
            
            let workouts = try await healthKitManager.fetchWorkouts(
                startDate: startDate,
                endDate: endDate
            )
            
            // Fetch from Strava
            var stravaActivities: [StravaActivity] = []
            if stravaManager.isAuthenticated {
                do {
                    stravaActivities = try await stravaManager.fetchActivities(page: 1, perPage: 100)
                } catch {
                    print("⚠️ Strava fetch failed: \(error.localizedDescription)")
                }
            }
            
            // Fetch nutrition
            let nutrition = await healthKitManager.fetchNutrition(
                startDate: startDate,
                endDate: endDate
            )
            
            print("✅ Data fetched successfully")
            print("   • Resting HR: \(restingHR.count) points")
            print("   • HRV: \(hrv.count) points")
            print("   • Sleep: \(sleep.count) nights")
            print("   • Workouts: \(workouts.count)")
            print("   • Strava: \(stravaActivities.count)")
            
            // Analyze readiness
            readinessScore = readinessAnalyzer.analyzeReadiness(
                restingHR: restingHR,
                hrv: hrv,
                sleep: sleep,
                workouts: workouts,
                stravaActivities: stravaActivities,
                nutrition: nutrition
            )
            
            // Discover patterns
            performanceWindows = patternAnalyzer.discoverPerformanceWindows(
                workouts: workouts,
                activities: stravaActivities,
                sleep: sleep,
                nutrition: nutrition
            )
            
            optimalTimings = patternAnalyzer.discoverOptimalTiming(
                workouts: workouts,
                activities: stravaActivities
            )
            
            workoutSequences = patternAnalyzer.discoverWorkoutSequences(
                workouts: workouts,
                activities: stravaActivities
            )
            
            // Generate form indicator
            if let readiness = readinessScore {
                formIndicator = generateFormIndicator(from: readiness, workouts: workouts + stravaActivities.compactMap { WorkoutData(from: $0) })
            }
            
            isLoading = false
            // ── ML prediction ──
            await trainAndPredict()

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            print("❌ Analysis failed: \(error)")
        }
    }
    
    private func generateFormIndicator(
        from readiness: ReadinessAnalyzer.ReadinessScore,
        workouts: [WorkoutData]
    ) -> ReadinessAnalyzer.FormIndicator {
        
        let status: ReadinessAnalyzer.FormIndicator.FormStatus
        let riskLevel: ReadinessAnalyzer.FormIndicator.RiskLevel
        let optimalWindow: String
        
        // Determine status
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
        
        // Calculate days in status (simplified)
        let daysInStatus = 1 // Would need historical tracking
        
        return ReadinessAnalyzer.FormIndicator(
            status: status,
            daysInStatus: daysInStatus,
            optimalActionWindow: optimalWindow,
            riskLevel: riskLevel
        )
    }
    
    @MainActor
    private func trainAndPredict() async {
        let cache = PredictionCache.shared

        // ── Build fingerprint from current data ──
        let fp = PredictionCache.fingerprint(
            workoutCount: workouts.count + stravaActivities.count,
            sleepCount:   sleepData.count,
            hrvCount:     hrvData.count,
            rhrCount:     restingHeartRateData.count
        )

        // ── Train only if data changed since last time ──
        if !cache.isUpToDate(fingerprint: fp) {
            do {
                let models = try await PerformancePredictor.train(
                    sleepData:         sleepData,
                    hrvData:           hrvData,
                    restingHRData:     restingHeartRateData,
                    healthKitWorkouts: workouts,
                    stravaActivities:  stravaActivities
                )
                cache.store(models: models, fingerprint: fp)
            } catch {
                cache.storeError(error)
                mlError = error.localizedDescription
                mlPrediction = nil
                mlFeatureWeights = nil
                return
            }
        }

        // ── Predict using today's conditions ──
        //    Use the most recent sleep / HRV / RHR values as inputs.
        guard let lastSleep = sleepData.last?.value,
              let lastHRV   = hrvData.last?.value,
              let lastRHR   = restingHeartRateData.last?.value else {
            mlError = "Need sleep, HRV, and resting HR data to predict"
            mlPrediction = nil
            mlFeatureWeights = nil
            return
        }

        // Predict for both Run and Ride; show whichever model exists
        let activityTypes = ["Run", "Ride"]
        for activityType in activityTypes {
            do {
                let prediction = try PerformancePredictor.predict(
                    models:       cache.models,
                    activityType: activityType,
                    sleepHours:   lastSleep,
                    hrvMs:        lastHRV,
                    restingHR:    lastRHR
                )
                mlPrediction    = prediction
                mlFeatureWeights = cache.models.first?.featureWeights
                mlError         = nil
                cache.storePrediction(prediction)
                print("🧠 Predicted \(activityType): \(prediction.predictedPerformance) \(prediction.unit)")
                return   // First successful prediction wins
            } catch {
                continue // Try next activity type
            }
        }

        mlError = "No trained model available for prediction"
    }
}
