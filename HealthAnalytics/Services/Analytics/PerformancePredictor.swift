//
//  PerformancePredictor.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/1/26.
//
//  Core ML-based performance prediction. Trains a regression model on-device
//  using sleep, HRV, and resting HR as features → workout performance as target.
//  Falls back to RandomForest when linear assumptions don't hold.
//

import Foundation
import CreateML
import CoreML
import HealthKit
import TabularData

// MARK: - Public API

struct PerformancePredictor {
    
    // MARK: - Models
    
    /// A single assembled training row, before it becomes an MLDataTable.
    private struct TrainingRow {
        let sleepHours:  Double   // previous night
        let hrvMs:       Double   // same day as workout
        let restingHR:   Double   // same day as workout
        let acwr:        Double   // Fatigue/Load metric
        let carbs:       Double   // Fueling metric
        let performance: Double   // speed (mph) or power (W) depending on activity
        let activityType: String  // "Run" or "Ride"
    }
    
    /// What the model learned — surfaced so the UI can show feature importance.
    struct TrainedModel {
        let model:            MLModel
        let activityType:     String          // "Run", "Ride", or "All"
        let sampleCount:      Int
        let rMeanSquaredError: Double         // lower = better fit
        let featureWeights:   FeatureWeights  // relative importance of each input
        let trainedAt:        Date
    }
    
    struct FeatureWeights {
        let sleep:     Double   // normalised 0…1
        let hrv:       Double
        let restingHR: Double
        let acwr:      Double
        let carbs:     Double
        
        var dominantFeature: String {
            let weights = ["Sleep": sleep, "HRV": hrv, "Resting HR": restingHR, "Fatigue (ACWR)": acwr, "Carbs": carbs]
            return weights.max(by: { $0.value < $1.value })?.key ?? "HRV"
        }
    }
    
    /// Result handed back to the UI after a prediction call.
    struct Prediction {
        let predictedPerformance: Double
        let activityType:         String
        let unit:                 String      // "mph" or "W"
        let confidence:           Confidence
        let inputs:               PredictionInputs
    }
    
    struct PredictionInputs {
        let sleepHours: Double
        let hrvMs:      Double
        let restingHR:  Double
        let acwr:       Double
        let carbs:      Double
    }
    
    enum Confidence: String {
        case high    = "High"     // ≥20 training samples
        case medium  = "Medium"   // 15–19
        case low     = "Low"      // 10–14
    }
    
    enum PredictorError: Error, LocalizedError {
        case insufficientData(count: Int, required: Int)
        case noTrainedModel
        case trainingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .insufficientData(let count, let required):
                return "Need \(required) workouts with full data to train (have \(count))"
            case .noTrainedModel:
                return "No trained model available — call train() first"
            case .trainingFailed(let msg):
                return "Training failed: \(msg)"
            }
        }
    }
    
    // MARK: - Minimum sample thresholds
    
    private static let minSamples     = 10
    private static let highConfidence = 20
    private static let medConfidence  = 15
    
    // MARK: - Training
    
    /// Assembles rows from your existing data types, trains per-activity-type
    /// models (Run / Ride), and returns whichever fits best.
    /// If a single activity type has fewer than minSamples, it falls back to
    /// a combined "All" model.
    
    static func train(
        sleepData:            [HealthDataPoint],
        hrvData:              [HealthDataPoint],
        restingHRData:        [HealthDataPoint],
        healthKitWorkouts:    [WorkoutData],
        stravaActivities:     [StravaActivity], // Still here for signature, but unused
        nutritionData:        [DailyNutrition],
        readinessService:     PredictiveReadinessService
    ) async throws -> [TrainedModel] {
        
        let calendar = Calendar.current
        let sleepByDate  = buildDayLookup(sleepData,      calendar: calendar)
        let hrvByDate    = buildDayLookup(hrvData,        calendar: calendar)
        let rhrByDate    = buildDayLookup(restingHRData,  calendar: calendar)
        let carbsByDate  = buildNutritionLookup(nutritionData, calendar: calendar)
        
        var rows: [TrainingRow] = []
        
        print("🤖 PerformancePredictor: Starting training on \(healthKitWorkouts.count) total workouts...")

        // ── 1. USE THE MERGED WORKOUTS DIRECTLY ──
        var rejectedNoMetrics = 0
        var rejectedNoPerformance = 0

        for workout in healthKitWorkouts {
            // Map the internal type to the "Ride"/"Run" strings the predictor expects
            let activityType: String
            switch workout.workoutType {
            case .cycling: activityType = "Ride"
            case .running: activityType = "Run"
            default: continue // Skip walking/other
            }
            
            // Define the dates here so they are in scope for the guard and the function call
            let workoutDay = calendar.startOfDay(for: workout.startDate)
            let prevDay = calendar.date(byAdding: .day, value: -1, to: workoutDay)!
            
            // Pre-check for metrics here to avoid calling rowFrom unnecessarily
            guard sleepByDate[prevDay] != nil,
                  hrvByDate[workoutDay] != nil,
                  rhrByDate[workoutDay] != nil else {
                continue
            }
            
            if let row = rowFrom(
                workout: workout,
                activityType: activityType,
                sleepByDate: sleepByDate,
                hrvByDate: hrvByDate,
                rhrByDate: rhrByDate,
                carbsByDate: carbsByDate,
                healthKitWorkouts: healthKitWorkouts, // Pass the full array for ACWR calc
                readinessService: readinessService,
                calendar: calendar
            ) {
                rows.append(row)
            } else {
                rejectedNoPerformance += 1
            }
        }
        
        print("-----------------------------------------")
        print("🤖 ML TRAINING DEBUG:")
        print("   Initial Workouts: \(healthKitWorkouts.count)")
        print("   Rejected (Missing Sleep/HRV/RHR): \(rejectedNoMetrics)")
        print("   Rejected (No Power/Speed data): \(rejectedNoPerformance)")
        print("   Final Assembled Rows: \(rows.count)")
        print("-----------------------------------------")
        
        print("📊 PerformancePredictor: Assembled \(rows.count) training rows")
        
        // ── 2. Train models (Ride / Run) ──
        let runRows  = rows.filter { $0.activityType == "Run"  }
        let rideRows = rows.filter { $0.activityType == "Ride" }
        
        var models: [TrainedModel] = []
        let minSamples = 5 // Ensure this is low enough for your historical data
        
        if runRows.count >= minSamples {
            let m = try await trainModel(rows: runRows, activityType: "Run")
            models.append(m)
        }
        
        if rideRows.count >= minSamples {
            let m = try await trainModel(rows: rideRows, activityType: "Ride")
            models.append(m)
        }
        
        if models.isEmpty {
            print("⚠️ No models created. Check if Sleep/HRV/RHR overlap with workout dates.")
        }
        
        return models
    }
    
    // MARK: - Prediction
    
    /// Given current conditions, predict performance for a specific activity.
    /// Automatically selects the best matching model.
    static func predict(
        models:       [TrainedModel],
        activityType: String,
        sleepHours:   Double,
        hrvMs:        Double,
        restingHR:    Double,
        acwr:         Double,
        carbs:        Double
    ) throws -> Prediction {
        
        // Pick the most specific model: exact type match > "All"
        let model = models.first(where: { $0.activityType == activityType })
        ?? models.first(where: { $0.activityType == "All" })
        
        guard let chosen = model else {
            throw PredictorError.noTrainedModel
        }
        
        // Prepare the input dictionary with all 5 features
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "sleep_hours": MLFeatureValue(double: sleepHours),
            "hrv_ms":      MLFeatureValue(double: hrvMs),
            "resting_hr":  MLFeatureValue(double: restingHR),
            "acwr":        MLFeatureValue(double: acwr),
            "carbs":       MLFeatureValue(double: carbs)
        ])
        
        let prediction = try chosen.model.prediction(from: input)
        
        guard let predicted = prediction.featureValue(for: "performance")?.doubleValue else {
            throw PredictorError.trainingFailed("prediction returned nil")
        }
        
        let confidence: Confidence
        switch chosen.sampleCount {
        case highConfidence...: confidence = .high
        case medConfidence..<highConfidence: confidence = .medium
        default: confidence = .low
        }
        
        let unit = (chosen.activityType == "Ride") ? "W" : "mph"
        
        return Prediction(
            predictedPerformance: predicted,
            activityType:         chosen.activityType == "All" ? activityType : chosen.activityType,
            unit:                 unit,
            confidence:           confidence,
            inputs: PredictionInputs(
                sleepHours: sleepHours,
                hrvMs:      hrvMs,
                restingHR:  restingHR,
                acwr:       acwr,
                carbs:      carbs   
            )
        )
    }
    
    // MARK: - Private helpers
    
    /// Builds a [startOfDay → value] dictionary from an array of HealthDataPoints.
    private static func buildDayLookup(
        _ data:    [HealthDataPoint],
        calendar:  Calendar
    ) -> [Date: Double] {
        var lookup: [Date: Double] = [:]
        for point in data {
            let day = calendar.startOfDay(for: point.date)
            // If multiple samples in one day, keep the last one (most recent)
            lookup[day] = point.value
        }
        return lookup
    }
    
    private static func rowFrom(
        workout: WorkoutData,
        activityType: String,
        sleepByDate: [Date: Double],
        hrvByDate: [Date: Double],
        rhrByDate: [Date: Double],
        carbsByDate: [Date: Double],
        healthKitWorkouts: [WorkoutData],
        readinessService: PredictiveReadinessService,
        calendar: Calendar
    ) -> TrainingRow? {
        let workoutDate = workout.startDate
        let workoutDay = calendar.startOfDay(for: workoutDate)
        let prevDay = calendar.date(byAdding: .day, value: -1, to: workoutDay)!
        
        // Check for metrics.
        // If this fails, the workout is ignored by the ML trainer.
        guard let sleep = sleepByDate[prevDay],
              let hrv   = hrvByDate[workoutDay],
              let rhr   = rhrByDate[workoutDay] else {
            return nil
        }
        
        // FIX: Corrected parentheses for speed calculation
        let performanceMetric: Double
        if workout.workoutType == .cycling {
            performanceMetric = workout.averagePower ?? ((workout.totalDistance ?? 0) / workout.duration * 2.23694)
        } else {
            performanceMetric = ((workout.totalDistance ?? 0) / workout.duration * 2.23694)
        }
        
        // Ensure we don't divide by zero or use empty workouts
        guard performanceMetric > 0, workout.duration > 0 else { return nil }
        
        let historicalHK = healthKitWorkouts.filter { $0.startDate < workoutDate }
        let assessment = readinessService.calculateReadiness(
            stravaActivities: [],
            healthKitWorkouts: historicalHK
        )
        
        let fallbackCarbs = getAverageCarbs(carbsByDate)
        let carbs = carbsByDate[prevDay] ?? fallbackCarbs

        return TrainingRow(
            sleepHours:   sleep,
            hrvMs:        hrv,
            restingHR:    rhr,
            acwr:         assessment.acwr,
            carbs:        carbs,
            performance:  performanceMetric,
            activityType: activityType
        )
    }
    
    // Calculate a simple average to use as a fallback
    private static func getAverageCarbs(_ carbsByDate: [Date: Double]) -> Double {
        let values = carbsByDate.values.filter { $0 > 0 }
        guard !values.isEmpty else { return 250.0 } // Default baseline if NO data exists
        return values.reduce(0, +) / Double(values.count)
    }

    /// Trains a single model. Tries LinearRegressor first; if RMSE is poor
    /// relative to the target variance, falls back to RandomForestRegressor.
    private static func trainModel(
        rows:         [TrainingRow],
        activityType: String
    ) async throws -> TrainedModel {
        
        // ── Build the MLDataTable with 5 features ──
        let sleepCol:  [Double] = rows.map { $0.sleepHours  }
        let hrvCol:    [Double] = rows.map { $0.hrvMs       }
        let rhrCol:    [Double] = rows.map { $0.restingHR   }
        let acwrCol:   [Double] = rows.map { $0.acwr        } // NEW
        let carbsCol:  [Double] = rows.map { $0.carbs       } // NEW
        let perfCol:   [Double] = rows.map { $0.performance }
        
        var df = DataFrame()
        df.append(column: Column(name: "sleep_hours", contents: sleepCol))
        df.append(column: Column(name: "hrv_ms", contents: hrvCol))
        df.append(column: Column(name: "resting_hr", contents: rhrCol))
        df.append(column: Column(name: "acwr", contents: acwrCol))    // NEW
        df.append(column: Column(name: "carbs", contents: carbsCol))  // NEW
        df.append(column: Column(name: "performance", contents: perfCol))
        
        let featureColumns = ["sleep_hours", "hrv_ms", "resting_hr", "acwr", "carbs"]
        
        // ── Train Linear first ──
        let linear = try MLLinearRegressor(
            trainingData: df,
            targetColumn: "performance",
            featureColumns: featureColumns
        )
        let linearRMSE = linear.trainingMetrics.rootMeanSquaredError
        
        // ── Compute target variance to judge whether linear is good enough ──
        let perfValues = rows.map { $0.performance }
        let mean       = perfValues.reduce(0, +) / Double(perfValues.count)
        let variance   = perfValues.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(perfValues.count)
        let stdDev     = sqrt(variance)
        
        // If RMSE > 60 % of stdDev the linear model explains very little; try forest
        var chosenModel: MLModel
        var chosenRMSE  = linearRMSE
        
        if linearRMSE > stdDev * 0.6 {
            print("   ⚡ Linear RMSE (\(String(format: "%.2f", linearRMSE))) > 60% of stdDev — trying RandomForest")
            let forest = try MLRandomForestRegressor(
                trainingData: df,
                targetColumn: "performance",
                featureColumns: featureColumns
            )
            let forestRMSE = forest.trainingMetrics.rootMeanSquaredError
            
            if forestRMSE < linearRMSE {
                chosenModel = forest.model
                chosenRMSE  = forestRMSE
                print("   ✅ RandomForest won (RMSE \(String(format: "%.2f", forestRMSE)) vs \(String(format: "%.2f", linearRMSE)))")
            } else {
                chosenModel = linear.model
                print("   ✅ Linear held (RMSE \(String(format: "%.2f", linearRMSE)) vs \(String(format: "%.2f", forestRMSE)))")
            }
        } else {
            chosenModel = linear.model
            print("   ✅ Linear sufficient (RMSE \(String(format: "%.2f", linearRMSE)), stdDev \(String(format: "%.2f", stdDev)))")
        }
        
        // ── Extract approximate feature weights via single-feature variance ──
        let weights = computeFeatureWeights(rows: rows)
        
        return TrainedModel(
            model:             chosenModel,
            activityType:      activityType,
            sampleCount:       rows.count,
            rMeanSquaredError: chosenRMSE,
            featureWeights:    weights,
            trainedAt:         Date()
        )
    }
    
    private static func buildNutritionLookup(_ data: [DailyNutrition], calendar: Calendar) -> [Date: Double] {
        var lookup: [Date: Double] = [:]
        for point in data {
            lookup[calendar.startOfDay(for: point.date)] = point.totalCarbs
        }
        return lookup
    }
    
    /// Approximates feature importance by measuring how much each feature's
    /// variance correlates with performance variance (Pearson r²).
    /// Works for both Linear and RandomForest models.
    private static func computeFeatureWeights(rows: [TrainingRow]) -> FeatureWeights {
        let n = Double(rows.count)
        
        let perfValues = rows.map { $0.performance }
        let perfMean   = perfValues.reduce(0, +) / n
        
        func pearsonR2(_ feature: [Double]) -> Double {
            let fMean = feature.reduce(0, +) / n
            var num = 0.0, denF = 0.0, denP = 0.0
            for i in 0..<rows.count {
                let df = feature[i]    - fMean
                let dp = perfValues[i] - perfMean
                num  += df * dp
                denF += df * df
                denP += dp * dp
            }
            let denom = sqrt(denF * denP)
            guard denom > 0 else { return 0 }
            let r = num / denom
            return r * r   // r² ∈ [0, 1]
        }
        
        let rSleep = pearsonR2(rows.map { $0.sleepHours })
        let rHRV   = pearsonR2(rows.map { $0.hrvMs      })
        let rRHR   = pearsonR2(rows.map { $0.restingHR  })
        let rACWR  = pearsonR2(rows.map { $0.acwr       }) // NEW
        let rCarbs = pearsonR2(rows.map { $0.carbs      }) // NEW
        
        let total  = rSleep + rHRV + rRHR + rACWR + rCarbs
        
        guard total > 0 else {
            return FeatureWeights(sleep: 0.2, hrv: 0.2, restingHR: 0.2, acwr: 0.2, carbs: 0.2)
        }
        
        return FeatureWeights(
            sleep:     rSleep / total,
            hrv:       rHRV   / total,
            restingHR: rRHR   / total,
            acwr:      rACWR  / total,
            carbs:     rCarbs / total
        )
    }
}
