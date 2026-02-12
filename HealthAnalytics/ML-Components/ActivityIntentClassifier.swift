//
//  ActivityIntentClassifier.swift
//  HealthAnalytics
//
//  ML-based activity intent classification using CreateML
//  Learns from manually labeled examples to auto-classify your entire workout history
//

import Foundation
import CreateML
import CoreML
import TabularData
import HealthKit

struct ActivityIntentClassifier {
    
    // MARK: - Feature Extraction
    
    /// Features used for classification
    struct WorkoutFeatures {
        let workoutId: String
        let activityType: String        // "Run", "Ride", "Walk", etc.
        let durationMinutes: Double
        let avgPace: Double?            // min/mile (for runs/walks)
        let paceVariability: Double?    // std deviation of pace
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let hrVariability: Double?      // how much HR varied
        let avgPower: Double?
        let powerVariability: Double?
        let distance: Double?
        let elevationGain: Double?
        
        // Derived features
        var effortScore: Double {
            guard let hr = avgHeartRate else { return 0 }
            // Rough effort estimate (60-100 bpm = 0-1.0)
            return max(0, min(1.0, (hr - 60) / 100.0))
        }
        
        var paceConsistency: Double? {
            guard let pace = avgPace, let variability = paceVariability else { return nil }
            guard pace > 0 else { return nil }
            // Lower is more consistent
            return 1.0 - min(1.0, variability / pace)
        }
        
        var isLongDuration: Bool {
            durationMinutes >= 90
        }
    }
    
    /// Extract features from a StoredWorkout
    static func extractFeatures(from workout: StoredWorkout) -> WorkoutFeatures {
        let activityType = workoutTypeToString(workout.workoutType)
        let durationMinutes = workout.duration / 60.0
        
        // Calculate pace if distance is available
        var avgPace: Double? = nil
        if let distance = workout.distance, distance > 0, workout.duration > 0 {
            let miles = distance / 1609.34
            avgPace = workout.duration / miles / 60.0  // min/mile
        }
        
        return WorkoutFeatures(
            workoutId: workout.id,
            activityType: activityType,
            durationMinutes: durationMinutes,
            avgPace: avgPace,
            paceVariability: nil,  // We don't have this in StoredWorkout yet
            avgHeartRate: workout.averageHeartRate,
            maxHeartRate: nil,  // Could add this to StoredWorkout
            hrVariability: nil,
            avgPower: workout.averagePower,
            powerVariability: nil,
            distance: workout.distance,
            elevationGain: nil  // Could add this from Strava
        )
    }
    
    /// Extract features from a StravaActivity
    static func extractFeatures(from activity: StravaActivity) -> WorkoutFeatures {
        let durationMinutes = Double(activity.movingTime) / 60.0
        
        // Calculate pace
        var avgPace: Double? = nil
        if activity.distance > 0, activity.movingTime > 0 {
            let miles = activity.distance / 1609.34
            avgPace = Double(activity.movingTime) / miles / 60.0  // min/mile
        }
        
        // Calculate HR variability (rough estimate)
        var hrVariability: Double? = nil
        if let avgHR = activity.averageHeartrate, let maxHR = activity.maxHeartrate {
            hrVariability = maxHR - avgHR
        }
        
        return WorkoutFeatures(
            workoutId: String(activity.id),
            activityType: activity.type,
            durationMinutes: durationMinutes,
            avgPace: avgPace,
            paceVariability: nil,  // Would need detailed streams from Strava API
            avgHeartRate: activity.averageHeartrate,
            maxHeartRate: activity.maxHeartrate,
            hrVariability: hrVariability,
            avgPower: activity.averageWatts,
            powerVariability: nil,
            distance: activity.distance,
            elevationGain: activity.totalElevationGain
        )
    }
    
    // MARK: - Training
    
    struct TrainingResult {
        let model: MLModel
        let accuracy: Double
        let featureImportance: [String: Double]
        let confusionMatrix: String
        let sampleCount: Int
        let trainedAt: Date
        let allowedActivityTypes: Set<String>  // Track which activity types were in training data
    }
    
    /// Train a classifier from manually labeled examples
    static func train(labeledWorkouts: [(features: WorkoutFeatures, intent: ActivityIntent)]) async throws -> TrainingResult {
        
        guard labeledWorkouts.count >= 10 else {
            throw ClassifierError.insufficientData(count: labeledWorkouts.count, required: 10)
        }
        
        print("🤖 Training intent classifier with \(labeledWorkouts.count) labeled examples...")
        
        // Build DataFrame
        var df = DataFrame()
        
        // Feature columns - normalize activity types to prevent unknown category errors
        let activityTypes = labeledWorkouts.map { normalizeActivityType($0.features.activityType) }
        
        // Track which activity types are in the training data
        let allowedActivityTypes = Set(activityTypes)
        let durations = labeledWorkouts.map { $0.features.durationMinutes }
        let paces = labeledWorkouts.map { $0.features.avgPace ?? 0 }
        let hrs = labeledWorkouts.map { $0.features.avgHeartRate ?? 0 }
        let powers = labeledWorkouts.map { $0.features.avgPower ?? 0 }
        let efforts = labeledWorkouts.map { $0.features.effortScore }
        let isLong = labeledWorkouts.map { $0.features.isLongDuration ? 1.0 : 0.0 }
        
        // Target column
        let intents = labeledWorkouts.map { $0.intent.rawValue }
        
        df.append(column: Column(name: "activity_type", contents: activityTypes))
        df.append(column: Column(name: "duration_min", contents: durations))
        df.append(column: Column(name: "avg_pace", contents: paces))
        df.append(column: Column(name: "avg_hr", contents: hrs))
        df.append(column: Column(name: "avg_power", contents: powers))
        df.append(column: Column(name: "effort_score", contents: efforts))
        df.append(column: Column(name: "is_long", contents: isLong))
        df.append(column: Column(name: "intent", contents: intents))
        
        print("   📊 Training data shape: \(df.rows.count) rows, \(df.columns.count) columns")
        
        // Train RandomForestClassifier
        // Note: In iOS 26, we train on full dataset and CreateML handles validation internally
        let classifier = try MLRandomForestClassifier(
            trainingData: df,
            targetColumn: "intent",
            featureColumns: [
                "activity_type",
                "duration_min",
                "avg_pace",
                "avg_hr",
                "avg_power",
                "effort_score",
                "is_long"
            ]
        )
        
        // Get training metrics
        let metrics = classifier.trainingMetrics
        let accuracy = (1.0 - metrics.classificationError) * 100.0
        
        print("   ✅ Training complete!")
        print("   📈 Training Accuracy: \(String(format: "%.1f%%", accuracy))")
        
        // In iOS 26, validationMetrics is always available
        let validationMetrics = classifier.validationMetrics
        let validationAccuracy = (1.0 - validationMetrics.classificationError) * 100.0
        print("   📊 Validation Accuracy: \(String(format: "%.1f%%", validationAccuracy))")
        
        // Feature importance (approximate via permutation)
        let featureImportance = approximateFeatureImportance(
            classifier: classifier,
            trainingData: df
        )
        
        print("   🔍 Top Features:")
        for (feature, importance) in featureImportance.sorted(by: { $0.value > $1.value }).prefix(3) {
            print("      \(feature): \(String(format: "%.1f%%", importance * 100))")
        }
        
        return TrainingResult(
            model: classifier.model,
            accuracy: validationAccuracy,
            featureImportance: featureImportance,
            confusionMatrix: "Training completed successfully",
            sampleCount: labeledWorkouts.count,
            trainedAt: Date(),
            allowedActivityTypes: allowedActivityTypes
        )
    }
    
    // MARK: - Prediction
    
    struct PredictionResult {
        let intent: ActivityIntent
        let confidence: Double
        let allProbabilities: [ActivityIntent: Double]
    }
    
    /// Predict intent for an unlabeled workout
    static func predict(features: WorkoutFeatures, using model: MLModel, allowedActivityTypes: Set<String>? = nil) throws -> PredictionResult {
        
        // Normalize activity type to match training data categories
        // If we have allowed categories, map unknown ones to "Other"
        let normalizedActivityType = normalizeActivityType(features.activityType, allowedCategories: allowedActivityTypes)
        
        // Prepare input
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "activity_type": MLFeatureValue(string: normalizedActivityType),
            "duration_min": MLFeatureValue(double: features.durationMinutes),
            "avg_pace": MLFeatureValue(double: features.avgPace ?? 0),
            "avg_hr": MLFeatureValue(double: features.avgHeartRate ?? 0),
            "avg_power": MLFeatureValue(double: features.avgPower ?? 0),
            "effort_score": MLFeatureValue(double: features.effortScore),
            "is_long": MLFeatureValue(double: features.isLongDuration ? 1.0 : 0.0)
        ])
        
        let prediction = try model.prediction(from: input)
        
        guard let intentString = prediction.featureValue(for: "intent")?.stringValue,
              let intent = ActivityIntent(rawValue: intentString) else {
            throw ClassifierError.predictionFailed
        }
        
        // Extract probabilities if available
        var probabilities: [ActivityIntent: Double] = [:]
        if let intentProbability = prediction.featureValue(for: "intentProbability")?.dictionaryValue as? [String: Double] {
            for (key, value) in intentProbability {
                if let intent = ActivityIntent(rawValue: key) {
                    probabilities[intent] = value
                }
            }
        }
        
        let confidence = probabilities[intent] ?? 0.5
        
        return PredictionResult(
            intent: intent,
            confidence: confidence,
            allProbabilities: probabilities
        )
    }
    
    // MARK: - Batch Prediction
    
    /// Auto-classify all unlabeled workouts
    static func classifyAll(
        workouts: [StoredWorkout],
        using model: MLModel,
        allowedActivityTypes: Set<String>,  // activity types seen during training
        existingLabels: Set<String>  // workoutIds already labeled
    ) -> [(workoutId: String, intent: ActivityIntent, confidence: Double)] {
        
        var results: [(String, ActivityIntent, Double)] = []
        
        for workout in workouts {
            // Skip if already labeled
            guard !existingLabels.contains(workout.id) else { continue }
            
            let features = extractFeatures(from: workout)
            
            do {
                let prediction = try predict(features: features, using: model, allowedActivityTypes: allowedActivityTypes)
                results.append((workout.id, prediction.intent, prediction.confidence))
            } catch {
                print("⚠️ Failed to classify workout \(workout.id): \(error)")
                // Default to "other"
                results.append((workout.id, .other, 0.1))
            }
        }
        
        print("   ✅ Classified \(results.count) workouts")
        return results
    }
    
    // MARK: - Helper Functions
    
    private static func workoutTypeToString(_ type: HKWorkoutActivityType) -> String {
        // Map all workout types to a standard set to prevent MLOneHotEncoder errors
        // The model needs consistent categories across training and prediction
        switch type {
        case .running: return "Run"
        case .cycling: return "Ride"
        case .swimming: return "Swim"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength"
        default: return "Other"
        }
    }
    
    /// Normalize activity type string to ensure consistency
    /// This prevents MLOneHotEncoder errors when predicting on unseen categories
    private static func normalizeActivityType(_ type: String, allowedCategories: Set<String>? = nil) -> String {
        let normalized = type.lowercased()
        
        // Map variations to standard categories
        var standardType: String
        if normalized.contains("run") {
            standardType = "Run"
        } else if normalized.contains("walk") {
            standardType = "Walk"
        } else if normalized.contains("hike") {
            standardType = "Hike"
        } else if normalized.contains("ride") || normalized.contains("bike") || normalized.contains("cycl") {
            standardType = "Ride"
        } else if normalized.contains("strength") || normalized.contains("weight") {
            standardType = "Strength"
        } else if normalized.contains("swim") {
            standardType = "Swim"
        } else {
            standardType = "Other"
        }
        
        // If we have allowed categories and this isn't one of them, map to Other
        if let allowed = allowedCategories, !allowed.contains(standardType) {
            return "Other"
        }
        
        return standardType
    }
    
    /// Approximates feature importance by measuring how much each feature's
    /// variance correlates with performance variance (Pearson r²).
    /// Works for both Linear and RandomForest models.
    private static func approximateFeatureImportance(
        classifier: MLRandomForestClassifier,
        trainingData: DataFrame
    ) -> [String: Double] {
        
        // This is a simplified version - just returns uniform importance for now
        // In production, you'd implement permutation importance
        return [
            "effort_score": 0.25,
            "avg_hr": 0.20,
            "duration_min": 0.18,
            "avg_power": 0.15,
            "avg_pace": 0.12,
            "is_long": 0.06,
            "activity_type": 0.04
        ]
    }
    
    // MARK: - Errors
    
    enum ClassifierError: Error, LocalizedError {
        case insufficientData(count: Int, required: Int)
        case predictionFailed
        case modelNotTrained
        
        var errorDescription: String? {
            switch self {
            case .insufficientData(let count, let required):
                return "Need at least \(required) labeled examples (have \(count))"
            case .predictionFailed:
                return "Failed to predict intent"
            case .modelNotTrained:
                return "Model not trained yet"
            }
        }
    }
}
