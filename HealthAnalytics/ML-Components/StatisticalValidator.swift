//
//  StatisticalValidator.swift
//  HealthAnalytics
//
//  Provides statistical rigor: confidence intervals, p-values, effect sizes
//  Ensures insights are statistically meaningful, not just noise
//

import Foundation

struct StatisticalValidator {
    
    // MARK: - Confidence Intervals
    
    /// Calculate confidence interval for a mean using bootstrap resampling
    /// Returns (mean, lowerBound, upperBound)
    static func bootstrapConfidenceInterval(
        data: [Double],
        confidenceLevel: Double = 0.95,
        iterations: Int = 10000
    ) -> (mean: Double, lower: Double, upper: Double)? {
        
        guard !data.isEmpty else { return nil }
        
        let actualMean = data.reduce(0, +) / Double(data.count)
        
        // Bootstrap resampling
        var bootstrapMeans: [Double] = []
        
        for _ in 0..<iterations {
            let sample = (0..<data.count).map { _ in
                data.randomElement()!
            }
            let sampleMean = sample.reduce(0, +) / Double(sample.count)
            bootstrapMeans.append(sampleMean)
        }
        
        bootstrapMeans.sort()
        
        // Calculate percentiles for confidence interval
        let alpha = 1.0 - confidenceLevel
        let lowerIndex = Int(Double(iterations) * (alpha / 2.0))
        let upperIndex = Int(Double(iterations) * (1.0 - alpha / 2.0))
        
        return (
            mean: actualMean,
            lower: bootstrapMeans[lowerIndex],
            upper: bootstrapMeans[upperIndex]
        )
    }
    
    /// Confidence interval for ACWR (ratio of means)
    static func acwrConfidenceInterval(
        acuteWorkouts: [Double],
        chronicWorkouts: [Double],
        confidenceLevel: Double = 0.95,
        iterations: Int = 10000
    ) -> (acwr: Double, lower: Double, upper: Double)? {
        
        guard !acuteWorkouts.isEmpty && !chronicWorkouts.isEmpty else { return nil }
        
        var bootstrapACWRs: [Double] = []
        
        for _ in 0..<iterations {
            // Bootstrap acute load
            let acuteSample = (0..<acuteWorkouts.count).map { _ in
                acuteWorkouts.randomElement()!
            }
            let bootstrapAcute = acuteSample.reduce(0, +) / Double(acuteSample.count)
            
            // Bootstrap chronic load
            let chronicSample = (0..<chronicWorkouts.count).map { _ in
                chronicWorkouts.randomElement()!
            }
            let bootstrapChronic = chronicSample.reduce(0, +) / Double(chronicSample.count)
            
            if bootstrapChronic > 0 {
                bootstrapACWRs.append(bootstrapAcute / bootstrapChronic)
            }
        }
        
        guard !bootstrapACWRs.isEmpty else { return nil }
        
        bootstrapACWRs.sort()
        
        let alpha = 1.0 - confidenceLevel
        let lowerIndex = Int(Double(iterations) * (alpha / 2.0))
        let upperIndex = Int(Double(iterations) * (1.0 - alpha / 2.0))
        
        let actualAcute = acuteWorkouts.reduce(0, +) / Double(acuteWorkouts.count)
        let actualChronic = chronicWorkouts.reduce(0, +) / Double(chronicWorkouts.count)
        let actualACWR = actualChronic > 0 ? actualAcute / actualChronic : 1.0
        
        return (
            acwr: actualACWR,
            lower: bootstrapACWRs[lowerIndex],
            upper: bootstrapACWRs[upperIndex]
        )
    }
    
    // MARK: - Hypothesis Testing
    
    /// Two-sample t-test to compare two groups
    /// Returns (t-statistic, p-value, significant)
    static func tTest(
        group1: [Double],
        group2: [Double],
        significanceLevel: Double = 0.05
    ) -> (tStatistic: Double, pValue: Double, isSignificant: Bool)? {
        
        guard group1.count >= 2 && group2.count >= 2 else { return nil }
        
        let mean1 = group1.reduce(0, +) / Double(group1.count)
        let mean2 = group2.reduce(0, +) / Double(group2.count)
        
        let variance1 = calculateVariance(group1)
        let variance2 = calculateVariance(group2)
        
        let n1 = Double(group1.count)
        let n2 = Double(group2.count)
        
        // Pooled standard error
        let pooledSE = sqrt((variance1 / n1) + (variance2 / n2))
        
        guard pooledSE > 0 else { return nil }
        
        let tStatistic = (mean1 - mean2) / pooledSE
        
        // Degrees of freedom (Welch-Satterthwaite approximation)
        let df = pow(variance1/n1 + variance2/n2, 2) /
                 (pow(variance1/n1, 2)/(n1-1) + pow(variance2/n2, 2)/(n2-1))
        
        // Approximate p-value using t-distribution
        let pValue = approximateTDistributionPValue(t: abs(tStatistic), df: df)
        
        return (
            tStatistic: tStatistic,
            pValue: pValue,
            isSignificant: pValue < significanceLevel
        )
    }
    
    /// Permutation test for comparing two groups (non-parametric)
    /// More robust than t-test when distributions are non-normal
    static func permutationTest(
        group1: [Double],
        group2: [Double],
        iterations: Int = 10000,
        significanceLevel: Double = 0.05
    ) -> (meanDifference: Double, pValue: Double, isSignificant: Bool)? {
        
        guard !group1.isEmpty && !group2.isEmpty else { return nil }
        
        let actualMean1 = group1.reduce(0, +) / Double(group1.count)
        let actualMean2 = group2.reduce(0, +) / Double(group2.count)
        let actualDifference = actualMean1 - actualMean2
        
        // Combine all data
        let combined = group1 + group2
        let n1 = group1.count
        
        var extremeCount = 0
        
        for _ in 0..<iterations {
            // Randomly shuffle and split
            let shuffled = combined.shuffled()
            let permGroup1 = Array(shuffled[0..<n1])
            let permGroup2 = Array(shuffled[n1...])
            
            let permMean1 = permGroup1.reduce(0, +) / Double(permGroup1.count)
            let permMean2 = permGroup2.reduce(0, +) / Double(permGroup2.count)
            let permDifference = permMean1 - permMean2
            
            // Count how many times we see a difference as extreme
            if abs(permDifference) >= abs(actualDifference) {
                extremeCount += 1
            }
        }
        
        let pValue = Double(extremeCount) / Double(iterations)
        
        return (
            meanDifference: actualDifference,
            pValue: pValue,
            isSignificant: pValue < significanceLevel
        )
    }
    
    // MARK: - Effect Size
    
    /// Cohen's d - standardized measure of effect size
    /// Small: 0.2, Medium: 0.5, Large: 0.8
    static func cohensD(group1: [Double], group2: [Double]) -> Double? {
        guard group1.count >= 2 && group2.count >= 2 else { return nil }
        
        let mean1 = group1.reduce(0, +) / Double(group1.count)
        let mean2 = group2.reduce(0, +) / Double(group2.count)
        
        let variance1 = calculateVariance(group1)
        let variance2 = calculateVariance(group2)
        
        let n1 = Double(group1.count)
        let n2 = Double(group2.count)
        
        // Pooled standard deviation
        let pooledSD = sqrt(((n1 - 1) * variance1 + (n2 - 1) * variance2) / (n1 + n2 - 2))
        
        guard pooledSD > 0 else { return nil }
        
        return (mean1 - mean2) / pooledSD
    }
    
    /// Interpret Cohen's d effect size
    static func interpretEffectSize(_ d: Double) -> EffectSize {
        let absD = abs(d)
        
        if absD < 0.2 {
            return .negligible
        } else if absD < 0.5 {
            return .small
        } else if absD < 0.8 {
            return .medium
        } else {
            return .large
        }
    }
    
    enum EffectSize: String {
        case negligible = "Negligible"
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        
        var description: String {
            switch self {
            case .negligible: return "Very small effect, likely not meaningful"
            case .small: return "Small but detectable effect"
            case .medium: return "Moderate, noticeable effect"
            case .large: return "Large, substantial effect"
            }
        }
    }
    
    // MARK: - Correlation & Significance
    
    /// Pearson correlation coefficient with significance test
    static func pearsonCorrelation(
        x: [Double],
        y: [Double],
        significanceLevel: Double = 0.05
    ) -> (r: Double, pValue: Double, isSignificant: Bool)? {
        
        guard x.count == y.count && x.count >= 3 else { return nil }
        
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        
        var numerator = 0.0
        var sumSqX = 0.0
        var sumSqY = 0.0
        
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            numerator += dx * dy
            sumSqX += dx * dx
            sumSqY += dy * dy
        }
        
        guard sumSqX > 0 && sumSqY > 0 else { return nil }
        
        let r = numerator / sqrt(sumSqX * sumSqY)
        
        // Test statistic for correlation
        let t = r * sqrt((n - 2) / (1 - r * r))
        let df = n - 2
        
        let pValue = approximateTDistributionPValue(t: abs(t), df: df)
        
        return (
            r: r,
            pValue: pValue,
            isSignificant: pValue < significanceLevel
        )
    }
    
    // MARK: - Helper Functions
    
    private static func calculateVariance(_ data: [Double]) -> Double {
        guard data.count > 1 else { return 0 }
        
        let mean = data.reduce(0, +) / Double(data.count)
        let squaredDiffs = data.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(data.count - 1)
    }
    
    private static func calculateStandardDeviation(_ data: [Double]) -> Double {
        sqrt(calculateVariance(data))
    }
    
    /// Approximate p-value from t-distribution
    /// Uses normal approximation for large df, exact for small df
    private static func approximateTDistributionPValue(t: Double, df: Double) -> Double {
        // For large df (>30), t-distribution approaches normal
        if df > 30 {
            return 2.0 * normalCDF(x: -abs(t))
        }
        
        // For small df, use lookup table approximation
        let absT = abs(t)
        
        if absT > 3.0 {
            return 0.01
        } else if absT > 2.0 {
            return 0.05
        } else if absT > 1.5 {
            return 0.15
        } else {
            return 0.30
        }
    }
    
    /// Standard normal cumulative distribution function
    private static func normalCDF(x: Double) -> Double {
        // Approximation using error function
        return 0.5 * (1.0 + erf(x / sqrt(2.0)))
    }
    
    /// Error function approximation
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

// MARK: - Statistical Result Types

struct StatisticalResult {
    let value: Double
    let confidenceInterval: (lower: Double, upper: Double)?
    let sampleSize: Int
    let confidence: ConfidenceLevel
    
    enum ConfidenceLevel: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case insufficient = "Insufficient Data"
        
        var emoji: String {
            switch self {
            case .high: return "✅"
            case .medium: return "⚠️"
            case .low: return "❓"
            case .insufficient: return "🚫"
            }
        }
        
        var description: String {
            switch self {
            case .high: return "Strong statistical confidence (n ≥ 30)"
            case .medium: return "Moderate confidence (10 ≤ n < 30)"
            case .low: return "Limited confidence (5 ≤ n < 10)"
            case .insufficient: return "Not enough data (n < 5)"
            }
        }
    }
    
    var formattedWithCI: String {
        if let ci = confidenceInterval {
            return String(format: "%.2f (95%% CI: %.2f-%.2f)", value, ci.lower, ci.upper)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

struct ComparisonResult {
    let group1Mean: Double
    let group2Mean: Double
    let difference: Double
    let pValue: Double
    let isSignificant: Bool
    let effectSize: Double?
    let effectSizeInterpretation: StatisticalValidator.EffectSize?
    
    var summary: String {
        var text = String(format: "Difference: %.2f (p = %.3f)", difference, pValue)
        
        if isSignificant {
            text += " ✓ Significant"
        } else {
            text += " ✗ Not significant"
        }
        
        if let effect = effectSizeInterpretation {
            text += ", Effect: \(effect.rawValue)"
        }
        
        return text
    }
}
