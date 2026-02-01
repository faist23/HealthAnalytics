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

// MARK: - Public API

struct PerformancePredictor {

    // MARK: - Models

    /// A single assembled training row, before it becomes an MLDataTable.
    private struct TrainingRow {
        let sleepHours:  Double   // previous night
        let hrvMs:       Double   // same day as workout
        let restingHR:   Double   // same day as workout
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

        /// Human-readable label for the single most important feature.
        var dominantFeature: String {
            let max = Swift.max(sleep, hrv, restingHR)
            if max == sleep     { return "Sleep" }
            if max == hrv       { return "HRV" }
            return "Resting HR"
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
        stravaActivities:     [StravaActivity]
    ) async throws -> [TrainedModel] {

        let calendar = Calendar.current

        // ── 1. Build date-keyed lookups (same pattern as CorrelationEngine) ──
        let sleepByDate  = buildDayLookup(sleepData,      calendar: calendar)
        let hrvByDate    = buildDayLookup(hrvData,        calendar: calendar)
        let rhrByDate    = buildDayLookup(restingHRData,  calendar: calendar)

        // ── 2. Deduplicate workouts so we don't double-count ──
        let (hkOnly, stravaOnly, matched) =
            WorkoutMatcher.deduplicateWorkouts(
                healthKitWorkouts: healthKitWorkouts,
                stravaActivities:  stravaActivities
            )

        // ── 3. Assemble training rows ──
        var rows: [TrainingRow] = []

        // Strava-only
        for activity in stravaOnly {
            if let row = rowFrom(stravaActivity: activity,
                                 sleepByDate: sleepByDate,
                                 hrvByDate: hrvByDate,
                                 rhrByDate: rhrByDate,
                                 calendar: calendar) {
                rows.append(row)
            }
        }

        // HealthKit-only
        for workout in hkOnly {
            if let row = rowFrom(hkWorkout: workout,
                                 sleepByDate: sleepByDate,
                                 hrvByDate: hrvByDate,
                                 rhrByDate: rhrByDate,
                                 calendar: calendar) {
                rows.append(row)
            }
        }

        // Matched pairs — prefer the richer source (same logic as CorrelationEngine)
        for matchedPair in matched {
            let best = WorkoutMatcher.selectBestWorkout(from: matchedPair)
            switch best {
            case .healthKit(let workout):
                if let row = rowFrom(hkWorkout: workout,
                                     sleepByDate: sleepByDate,
                                     hrvByDate: hrvByDate,
                                     rhrByDate: rhrByDate,
                                     calendar: calendar) {
                    rows.append(row)
                }
            case .strava(let activity):
                if let row = rowFrom(stravaActivity: activity,
                                     sleepByDate: sleepByDate,
                                     hrvByDate: hrvByDate,
                                     rhrByDate: rhrByDate,
                                     calendar: calendar) {
                    rows.append(row)
                }
            }
        }

        print("📊 PerformancePredictor: assembled \(rows.count) training rows")

        // ── 4. Split by activity type, train per-type if possible ──
        let runRows  = rows.filter { $0.activityType == "Run"  }
        let rideRows = rows.filter { $0.activityType == "Ride" }

        var models: [TrainedModel] = []

        if runRows.count >= minSamples {
            let m = try await trainModel(rows: runRows, activityType: "Run")
            models.append(m)
            print("   ✅ Run model trained on \(runRows.count) samples")
        }

        if rideRows.count >= minSamples {
            let m = try await trainModel(rows: rideRows, activityType: "Ride")
            models.append(m)
            print("   ✅ Ride model trained on \(rideRows.count) samples")
        }

        // If neither type had enough data alone, try a combined model
        if models.isEmpty {
            guard rows.count >= minSamples else {
                throw PredictorError.insufficientData(count: rows.count, required: minSamples)
            }
            let m = try await trainModel(rows: rows, activityType: "All")
            models.append(m)
            print("   ✅ Combined model trained on \(rows.count) samples")
        }

        return models
    }

    // MARK: - Prediction

    /// Given current conditions, predict performance for a specific activity.
    /// Automatically selects the best matching model.
    static func predict(
        models:      [TrainedModel],
        activityType: String,
        sleepHours:  Double,
        hrvMs:       Double,
        restingHR:   Double
    ) throws -> Prediction {

        // Pick the most specific model: exact type match > "All"
        let model = models.first(where: { $0.activityType == activityType })
                 ?? models.first(where: { $0.activityType == "All" })

        guard let chosen = model else {
            throw PredictorError.noTrainedModel
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "sleep_hours": MLFeatureValue(double: sleepHours),
            "hrv_ms":      MLFeatureValue(double: hrvMs),
            "resting_hr":  MLFeatureValue(double: restingHR)
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
                restingHR:  restingHR
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

    /// Converts a StravaActivity into a TrainingRow, or nil if data is missing.
    private static func rowFrom(
        stravaActivity activity: StravaActivity,
        sleepByDate:  [Date: Double],
        hrvByDate:    [Date: Double],
        rhrByDate:    [Date: Double],
        calendar:     Calendar
    ) -> TrainingRow? {
        guard let date = activity.startDateFormatted else { return nil }
        guard activity.type == "Run" || activity.type == "Ride" else { return nil }
        guard let speed = activity.averageSpeed, speed > 0 else { return nil }

        let workoutDay = calendar.startOfDay(for: date)
        let prevDay    = calendar.date(byAdding: .day, value: -1, to: workoutDay)!

        guard let sleep  = sleepByDate[prevDay],
              let hrv    = hrvByDate[workoutDay],
              let rhr    = rhrByDate[workoutDay] else { return nil }

        let perf: Double
        if activity.type == "Run" {
            perf = speed * 2.23694   // m/s → mph
        } else {
            perf = activity.averageWatts ?? (speed * 2.23694)
        }

        return TrainingRow(
            sleepHours:   sleep,
            hrvMs:        hrv,
            restingHR:    rhr,
            performance:  perf,
            activityType: activity.type
        )
    }

    /// Converts a HealthKit WorkoutData into a TrainingRow, or nil if data is missing.
    private static func rowFrom(
        hkWorkout workout: WorkoutData,
        sleepByDate:  [Date: Double],
        hrvByDate:    [Date: Double],
        rhrByDate:    [Date: Double],
        calendar:     Calendar
    ) -> TrainingRow? {
        let cardioTypes: [HKWorkoutActivityType] = [.running, .cycling]
        guard cardioTypes.contains(workout.workoutType) else { return nil }
        guard let distance = workout.totalDistance, distance > 0,
              workout.duration > 0 else { return nil }

        let workoutDay = calendar.startOfDay(for: workout.startDate)
        let prevDay    = calendar.date(byAdding: .day, value: -1, to: workoutDay)!

        guard let sleep = sleepByDate[prevDay],
              let hrv   = hrvByDate[workoutDay],
              let rhr   = rhrByDate[workoutDay] else { return nil }

        let speedMPH = (distance / workout.duration) * 2.23694

        // Use power if available (cycling), otherwise speed
        let perf: Double
        let activityType: String
        if workout.workoutType == .cycling {
            perf = workout.averagePower ?? speedMPH
            activityType = "Ride"
        } else {
            perf = speedMPH
            activityType = "Run"
        }

        return TrainingRow(
            sleepHours:   sleep,
            hrvMs:        hrv,
            restingHR:    rhr,
            performance:  perf,
            activityType: activityType
        )
    }

    /// Trains a single model. Tries LinearRegressor first; if RMSE is poor
    /// relative to the target variance, falls back to RandomForestRegressor.
    private static func trainModel(
        rows:         [TrainingRow],
        activityType: String
    ) async throws -> TrainedModel {

        // ── Build the MLDataTable ──
        let table = try MLDataTable(dictionary: [
            "sleep_hours": rows.map { $0.sleepHours  as Any },
            "hrv_ms":      rows.map { $0.hrvMs       as Any },
            "resting_hr":  rows.map { $0.restingHR   as Any },
            "performance": rows.map { $0.performance as Any }
        ])

        // ── Train Linear first ──
        let linear = try MLLinearRegressor(
            trainingData: table,
            targetColumn: "performance"
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
                trainingData: table,
                targetColumn: "performance"
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
            model:            chosenModel,
            activityType:     activityType,
            sampleCount:      rows.count,
            rMeanSquaredError: chosenRMSE,
            featureWeights:   weights,
            trainedAt:        Date()
        )
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
        let total  = rSleep + rHRV + rRHR

        guard total > 0 else {
            return FeatureWeights(sleep: 0.33, hrv: 0.33, restingHR: 0.34)
        }

        return FeatureWeights(
            sleep:     rSleep / total,
            hrv:       rHRV   / total,
            restingHR: rRHR   / total
        )
    }
}
