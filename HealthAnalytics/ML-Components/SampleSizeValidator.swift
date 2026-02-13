//
//  SampleSizeValidator.swift
//  HealthAnalytics
//
//  Ensures we have enough data before making claims
//  Prevents misleading insights from small sample sizes
//

import Foundation

struct SampleSizeValidator {
    
    // MARK: - Minimum Sample Size Requirements
    
    static let minimumForTTest = 5           // Absolute minimum for any statistical test
    static let minimumForCorrelation = 10    // Minimum for meaningful correlation
    static let minimumForRegression = 20     // Minimum for regression analysis
    static let minimumForMLTraining = 30     // Minimum for ML model training
    static let idealForPatternDiscovery = 50 // Ideal for discovering patterns
    
    // MARK: - Validation Methods
    
    /// Check if sample size is adequate for the analysis type
    static func validate(
        sampleSize: Int,
        analysisType: AnalysisType
    ) -> ValidationResult {
        
        let required = analysisType.minimumRequired
        let ideal = analysisType.idealSize
        
        if sampleSize < required {
            return ValidationResult(
                isValid: false,
                sampleSize: sampleSize,
                required: required,
                confidence: .insufficient,
                message: "Need at least \(required) data points for \(analysisType.rawValue). Currently have \(sampleSize)."
            )
        } else if sampleSize < ideal {
            return ValidationResult(
                isValid: true,
                sampleSize: sampleSize,
                required: required,
                confidence: sampleSize >= ideal / 2 ? .medium : .low,
                message: "Have \(sampleSize) data points. Confidence would improve with \(ideal)+ points."
            )
        } else {
            return ValidationResult(
                isValid: true,
                sampleSize: sampleSize,
                required: required,
                confidence: .high,
                message: "Excellent sample size (\(sampleSize) points) for \(analysisType.rawValue)."
            )
        }
    }
    
    /// Validate sample sizes for comparing two groups
    static func validateComparison(
        group1Size: Int,
        group2Size: Int,
        analysisType: AnalysisType = .comparison
    ) -> ValidationResult {
        
        let minSize = min(group1Size, group2Size)
        return validate(sampleSize: minSize, analysisType: analysisType)
    }
    
    /// Calculate statistical power for a given sample size
    /// Returns probability of detecting a true effect
    static func calculatePower(
        sampleSize: Int,
        expectedEffectSize: Double,
        significanceLevel: Double = 0.05
    ) -> Double {
        
        // Simplified power calculation
        // In production, use a proper power analysis library
        
        let noncentrality = expectedEffectSize * sqrt(Double(sampleSize) / 2.0)
        
        // Critical value for two-tailed test
        let criticalValue = 1.96 // For alpha = 0.05
        
        // Simplified power approximation using normal distribution
        let power = 1.0 - (0.5 * (1.0 + SampleSizeValidator.erf((criticalValue - noncentrality) / sqrt(2.0))))
        
        return max(0.0, min(1.0, power))
    }
    
    /// Recommend sample size for desired statistical power
    static func recommendedSampleSize(
        desiredPower: Double = 0.80,
        expectedEffectSize: Double,
        significanceLevel: Double = 0.05
    ) -> Int {
        
        // Binary search for required sample size
        var low = 5
        var high = 1000
        
        while low < high {
            let mid = (low + high) / 2
            let power = calculatePower(
                sampleSize: mid,
                expectedEffectSize: expectedEffectSize,
                significanceLevel: significanceLevel
            )
            
            if power < desiredPower {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        return low
    }
    
    // MARK: - Analysis Types
    
    enum AnalysisType: String {
        case basicStats = "basic statistics"
        case comparison = "group comparison"
        case correlation = "correlation analysis"
        case regression = "regression analysis"
        case mlTraining = "ML model training"
        case patternDiscovery = "pattern discovery"
        case intentClassification = "intent classification"
        
        var minimumRequired: Int {
            switch self {
            case .basicStats: return 5
            case .comparison: return 5
            case .correlation: return 10
            case .regression: return 20
            case .mlTraining: return 30
            case .patternDiscovery: return 20
            case .intentClassification: return 10
            }
        }
        
        var idealSize: Int {
            switch self {
            case .basicStats: return 30
            case .comparison: return 30
            case .correlation: return 30
            case .regression: return 50
            case .mlTraining: return 100
            case .patternDiscovery: return 50
            case .intentClassification: return 50
            }
        }
    }
    
    // MARK: - Validation Result
    
    struct ValidationResult {
        let isValid: Bool
        let sampleSize: Int
        let required: Int
        let confidence: ConfidenceLevel
        let message: String
        
        enum ConfidenceLevel {
            case high
            case medium
            case low
            case insufficient
            
            var emoji: String {
                switch self {
                case .high: return "✅"
                case .medium: return "⚠️"
                case .low: return "❓"
                case .insufficient: return "🚫"
                }
            }
            
            var color: String {
                switch self {
                case .high: return "green"
                case .medium: return "yellow"
                case .low: return "orange"
                case .insufficient: return "red"
                }
            }
        }
        
        var needsMoreData: Int? {
            guard !isValid else { return nil }
            return required - sampleSize
        }
    }
    
    // MARK: - Helper

    private static func erf(_ x: Double) -> Double {
        let a1 =  0.254829592
        let a2 = -0.284496736
        let a3 =  1.421413741
        let a4 = -1.453152027
        let a5 =  1.061405429
        let p  =  0.3275911
        
        let sign = x < 0 ? -1.0 : 1.0
        let absX = abs(x)
        
        let t = 1.0 / (1.0 + p * absX)
        let y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-absX * absX)
        
        return sign * y
    }
}

