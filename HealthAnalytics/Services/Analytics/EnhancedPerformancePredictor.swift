//
//  EnhancedPerformancePredictor.swift
//  HealthAnalytics
//
//  ML predictions with statistical uncertainty
//  Provides prediction intervals (not just point estimates)
//

import Foundation
import CreateML
import CoreML

extension PerformancePredictor {
    
    /// Enhanced prediction with uncertainty bounds
    struct PredictionWithUncertainty {
        let prediction: Prediction
        let predictionInterval: (lower: Double, upper: Double)?
        let modelUncertainty: ModelUncertainty
        
        struct ModelUncertainty {
            let rmse: Double
            let sampleSize: Int
            let confidence: StatisticalResult.ConfidenceLevel
            
            var description: String {
                "\(confidence.emoji) \(confidence) (\(sampleSize) training samples, RMSE: \(String(format: "%.1f", rmse)))"
            }
        }
        
        var formattedPrediction: String {
            if let interval = predictionInterval {
                return String(format: "%.1f %@ (95%% PI: %.1f-%.1f)", 
                            prediction.predictedPerformance,
                            prediction.unit,
                            interval.lower,
                            interval.upper)
            } else {
                return String(format: "%.1f %@", prediction.predictedPerformance, prediction.unit)
            }
        }
    }
    
    /// Make prediction with uncertainty quantification
    static func predictWithUncertainty(
        models: [TrainedModel],
        activityType: String,
        sleepHours: Double,
        hrvMs: Double,
        restingHR: Double,
        acwr: Double,
        carbs: Double
    ) throws -> PredictionWithUncertainty {
        
        // Get base prediction
        let basePrediction = try predict(
            models: models,
            activityType: activityType,
            sleepHours: sleepHours,
            hrvMs: hrvMs,
            restingHR: restingHR,
            acwr: acwr,
            carbs: carbs
        )
        
        // Find the model that was used
        guard let model = models.first(where: { $0.activityType == basePrediction.activityType }) else {
            throw PredictorError.noTrainedModel
        }
        
        // Calculate prediction interval using RMSE
        // For a 95% prediction interval: prediction ± 1.96 * RMSE
        let margin = 1.96 * model.rMeanSquaredError
        let predictionInterval = (
            lower: max(0, basePrediction.predictedPerformance - margin),
            upper: basePrediction.predictedPerformance + margin
        )
        
        // Determine confidence based on sample size
        let confidence: StatisticalResult.ConfidenceLevel
        if model.sampleCount >= 30 {
            confidence = .high
        } else if model.sampleCount >= 10 {
            confidence = .medium
        } else if model.sampleCount >= 5 {
            confidence = .low
        } else {
            confidence = .insufficient
        }
        
        let uncertainty = PredictionWithUncertainty.ModelUncertainty(
            rmse: model.rMeanSquaredError,
            sampleSize: model.sampleCount,
            confidence: confidence
        )
        
        return PredictionWithUncertainty(
            prediction: basePrediction,
            predictionInterval: predictionInterval,
            modelUncertainty: uncertainty
        )
    }
    
    /// Validate model quality before trusting predictions
    static func validateModelQuality(model: TrainedModel) -> ModelQualityReport {
        
        let sampleValidation = SampleSizeValidator.validate(
            sampleSize: model.sampleCount,
            analysisType: .mlTraining
        )
        
        // Check RMSE relative to typical values
        // For power: RMSE < 20W is good
        // For speed: RMSE < 0.5 mph is good
        let rmseQuality: RMSEQuality
        if model.activityType == "Ride" {
            rmseQuality = model.rMeanSquaredError < 15 ? .excellent :
                         (model.rMeanSquaredError < 25 ? .good : .poor)
        } else {
            rmseQuality = model.rMeanSquaredError < 0.4 ? .excellent :
                         (model.rMeanSquaredError < 0.7 ? .good : .poor)
        }
        
        return ModelQualityReport(
            activityType: model.activityType,
            sampleValidation: sampleValidation,
            rmseQuality: rmseQuality,
            rmse: model.rMeanSquaredError,
            shouldTrust: sampleValidation.isValid && rmseQuality != .poor
        )
    }
    
    enum RMSEQuality {
        case excellent
        case good
        case poor
        
        var description: String {
            switch self {
            case .excellent: return "Excellent model fit"
            case .good: return "Good model fit"
            case .poor: return "Poor model fit - predictions may be unreliable"
            }
        }
    }
    
    struct ModelQualityReport {
        let activityType: String
        let sampleValidation: SampleSizeValidator.ValidationResult
        let rmseQuality: RMSEQuality
        let rmse: Double
        let shouldTrust: Bool
        
        var summary: String {
            if shouldTrust {
                return "\(sampleValidation.confidence.emoji) \(rmseQuality.description) (n=\(sampleValidation.sampleSize), RMSE=\(String(format: "%.1f", rmse)))"
            } else {
                return "⚠️ \(rmseQuality.description) - need more data"
            }
        }
    }
}
