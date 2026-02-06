//
//  InjuryRiskCalculator.swift
//  HealthAnalytics
//
//  Created by Craig Faist.
//

import Foundation

class InjuryRiskCalculator {
    
    struct InjuryRiskAssessment {
        let riskLevel: RiskLevel
        let contributingFactors: [RiskFactor]
        let recommendation: String
        let score: Int // 0-100
    }
    
    enum RiskLevel: String {
        case low
        case moderate
        case high
        case veryHigh
        
        var color: String {
            switch self {
            case .low: return "green"
            case .moderate: return "yellow"
            case .high: return "orange"
            case .veryHigh: return "red"
            }
        }
        
        var label: String {
            switch self {
            case .low: return "Low Risk"
            case .moderate: return "Moderate Risk"
            case .high: return "High Risk"
            case .veryHigh: return "Very High Risk"
            }
        }
        
        var emoji: String {
            switch self {
            case .low: return "🛡️"
            case .moderate: return "⚠️"
            case .high: return "🚑"
            case .veryHigh: return "🏥"
            }
        }
    }
    
    struct RiskFactor: Identifiable {
        let id = UUID()
        let description: String
        let severity: Int // 1-10
    }
    
    func assessInjuryRisk(trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?,
                          recoveryStatus: [CorrelationEngine.RecoveryInsight],
                          trends: [MetricTrend]) -> InjuryRiskAssessment {
        
        var riskScore = 10 // Base line risk
        var factors: [RiskFactor] = []
        
        // 1. Analyze Training Load (ACWR)
        if let load = trainingLoad {
            if load.acuteChronicRatio > 1.5 {
                riskScore += 40
                factors.append(RiskFactor(description: "Acute load significantly exceeds chronic load (>1.5)", severity: 8))
            } else if load.acuteChronicRatio > 1.3 {
                riskScore += 20
                factors.append(RiskFactor(description: "Acute load is high relative to chronic load (>1.3)", severity: 5))
            } else if load.acuteChronicRatio < 0.8 {
                riskScore += 5
                factors.append(RiskFactor(description: "Undertraining may reduce resilience", severity: 2))
            }
        }
        
        // 2. Analyze Recovery Status
        // 🟢 FIXED: Check 'trend' enum (.fatigued) instead of 'status' string
        let strainedRecovery = recoveryStatus.filter { $0.trend == .fatigued }
        
        if !strainedRecovery.isEmpty {
            riskScore += 25
            factors.append(RiskFactor(description: "Biometrics indicate incomplete recovery", severity: 7))
        }
        
        // 3. Analyze Trends
        let rhrTrend = trends.first { $0.metricName == "Resting Heart Rate" }
        let hrvTrend = trends.first { $0.metricName == "HRV" }
        let sleepTrend = trends.first { $0.metricName == "Sleep Duration" }
        
        // RHR Trend Check
        if let rhr = rhrTrend, (rhr.status == .declining || rhr.status == .warning) {
            riskScore += 15
            factors.append(RiskFactor(description: "Resting Heart Rate trending upward", severity: 5))
        }
        
        // HRV Trend Check
        if let hrv = hrvTrend, (hrv.status == .declining || hrv.status == .warning) {
            riskScore += 15
            factors.append(RiskFactor(description: "HRV trending downward", severity: 6))
        }
        
        // Sleep Trend Check
        if let sleep = sleepTrend, (sleep.status == .declining || sleep.status == .warning) {
            riskScore += 10
            factors.append(RiskFactor(description: "Sleep duration trending downward", severity: 4))
        }
        
        // 4. Determine Level and Recommendation
        let level: RiskLevel
        let recommendation: String
        
        switch riskScore {
        case 0..<30:
            level = .low
            recommendation = "Maintain current training balance."
        case 30..<50:
            level = .moderate
            recommendation = "Monitor recovery closely. Ensure good sleep hygiene."
        case 50..<75:
            level = .high
            recommendation = "Consider reducing intensity or volume for 2-3 days."
        default:
            level = .veryHigh
            recommendation = "Immediate recovery advised. High risk of non-functional overreaching."
        }
        
        return InjuryRiskAssessment(
            riskLevel: level,
            contributingFactors: factors,
            recommendation: recommendation,
            score: min(riskScore, 100)
        )
    }
}
