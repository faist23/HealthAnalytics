//
//  InjuryRiskCalculator.swift
//  HealthAnalytics
//
//  Enhanced multi-factor injury risk model for endurance athletes
//  Based on latest sports science research
//

import Foundation
import SwiftUI

class InjuryRiskCalculator {
    
    struct InjuryRiskAssessment {
        let riskLevel: RiskLevel
        let contributingFactors: [RiskFactor]
        let recommendation: String
        let score: Int // 0-100
        
        // Enhanced metrics
        let loadRisk: Int           // 0-40 points from training load
        let recoveryRisk: Int       // 0-30 points from recovery status
        let trendRisk: Int          // 0-20 points from metric trends
        let monotonyRisk: Int       // 0-10 points from training monotony
        
        var detailedBreakdown: String {
            """
            Risk Breakdown:
            • Load: \(loadRisk)/40 pts
            • Recovery: \(recoveryRisk)/30 pts
            • Trends: \(trendRisk)/20 pts
            • Monotony: \(monotonyRisk)/10 pts
            Total: \(score)/100 pts
            """
        }
    }
    
    enum RiskLevel: String {
        case low
        case moderate
        case high
        case veryHigh
        
        var color: Color {
            switch self {
            case .low: return .green
            case .moderate: return .yellow
            case .high: return .orange
            case .veryHigh: return .red
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
        let category: Category
        
        enum Category {
            case load
            case recovery
            case trend
            case monotony
        }
    }
    
    func assessInjuryRisk(trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?,
                          recoveryStatus: [CorrelationEngine.RecoveryInsight],
                          trends: [MetricTrend]) -> InjuryRiskAssessment {
        
        var factors: [RiskFactor] = []
        
        // Component risk scores (add up to 100)
        var loadRisk = 0        // Max 40 points
        var recoveryRisk = 0    // Max 30 points
        var trendRisk = 0       // Max 20 points
        var monotonyRisk = 0    // Max 10 points
        
        // 1. ENHANCED LOAD ANALYSIS (40 points max)
        if let load = trainingLoad {
            // EWMA Ratio Analysis (primary - 25 points)
            let ewmaRatio = load.ewmaRatio
            if ewmaRatio > 1.5 {
                loadRisk += 25
                factors.append(RiskFactor(
                    description: "EWMA ratio critically high (\(String(format: "%.2f", ewmaRatio)))",
                    severity: 9,
                    category: .load
                ))
            } else if ewmaRatio > 1.3 {
                loadRisk += 18
                factors.append(RiskFactor(
                    description: "EWMA ratio elevated (\(String(format: "%.2f", ewmaRatio)))",
                    severity: 6,
                    category: .load
                ))
            } else if ewmaRatio > 1.15 {
                loadRisk += 10
                factors.append(RiskFactor(
                    description: "EWMA ratio moderately high (\(String(format: "%.2f", ewmaRatio)))",
                    severity: 4,
                    category: .load
                ))
            }
            
            // Monotony Analysis (10 points)
            if load.monotony > 2.5 {
                monotonyRisk += 10
                factors.append(RiskFactor(
                    description: "Very high training monotony (\(String(format: "%.1f", load.monotony)))",
                    severity: 7,
                    category: .monotony
                ))
            } else if load.monotony > 2.0 {
                monotonyRisk += 6
                factors.append(RiskFactor(
                    description: "High training monotony - add variety",
                    severity: 5,
                    category: .monotony
                ))
            }
            
            // Strain Analysis (5 points)
            if load.strain > 1500 {
                loadRisk += 5
                factors.append(RiskFactor(
                    description: "Very high strain score (\(String(format: "%.0f", load.strain)))",
                    severity: 6,
                    category: .load
                ))
            }
            
            // Weekly Load Spike (10 points)
            if load.weeklyLoadChange > 30 {
                loadRisk += 10
                factors.append(RiskFactor(
                    description: "Rapid load increase: +\(String(format: "%.0f", load.weeklyLoadChange))% this week",
                    severity: 8,
                    category: .load
                ))
            } else if load.weeklyLoadChange > 20 {
                loadRisk += 5
                factors.append(RiskFactor(
                    description: "Significant load increase: +\(String(format: "%.0f", load.weeklyLoadChange))%",
                    severity: 5,
                    category: .load
                ))
            }
        }
        
        // 2. RECOVERY STATUS ANALYSIS (30 points max)
        let strainedRecovery = recoveryStatus.filter { $0.trend == .fatigued }
        
        if !strainedRecovery.isEmpty {
            recoveryRisk += 20
            factors.append(RiskFactor(
                description: "Biometrics indicate incomplete recovery",
                severity: 8,
                category: .recovery
            ))
        }
        
        // Check for multiple poor recovery markers
        let poorRecoveryCount = recoveryStatus.filter { 
            $0.trend == .fatigued || $0.trend == .recovering 
        }.count
        
        if poorRecoveryCount >= 2 {
            recoveryRisk += 10
            factors.append(RiskFactor(
                description: "Multiple recovery metrics suppressed",
                severity: 7,
                category: .recovery
            ))
        }
        
        // 3. TREND ANALYSIS (20 points max)
        let rhrTrend = trends.first { $0.metricName == "Resting Heart Rate" }
        let hrvTrend = trends.first { $0.metricName == "HRV" }
        let sleepTrend = trends.first { $0.metricName == "Sleep Duration" }
        
        // RHR Trend Check (7 points)
        if let rhr = rhrTrend {
            if rhr.status == .warning {
                trendRisk += 7
                factors.append(RiskFactor(
                    description: "RHR trending upward (fatigue signal)",
                    severity: 6,
                    category: .trend
                ))
            } else if rhr.status == .declining {
                trendRisk += 4
                factors.append(RiskFactor(
                    description: "RHR slightly elevated",
                    severity: 4,
                    category: .trend
                ))
            }
        }
        
        // HRV Trend Check (8 points - most important)
        if let hrv = hrvTrend {
            if hrv.status == .warning {
                trendRisk += 8
                factors.append(RiskFactor(
                    description: "HRV trending downward (recovery incomplete)",
                    severity: 7,
                    category: .trend
                ))
            } else if hrv.status == .declining {
                trendRisk += 4
                factors.append(RiskFactor(
                    description: "HRV slightly suppressed",
                    severity: 4,
                    category: .trend
                ))
            }
        }
        
        // Sleep Trend Check (5 points)
        if let sleep = sleepTrend {
            if sleep.status == .warning {
                trendRisk += 5
                factors.append(RiskFactor(
                    description: "Sleep duration declining",
                    severity: 5,
                    category: .trend
                ))
            } else if sleep.status == .declining {
                trendRisk += 2
                factors.append(RiskFactor(
                    description: "Sleep slightly below normal",
                    severity: 3,
                    category: .trend
                ))
            }
        }
        
        // 4. CALCULATE TOTAL SCORE
        let totalScore = loadRisk + recoveryRisk + trendRisk + monotonyRisk
        
        // 5. DETERMINE LEVEL AND RECOMMENDATION
        let level: RiskLevel
        let recommendation: String
        
        switch totalScore {
        case 0..<25:
            level = .low
            recommendation = "Low injury risk. Maintain current training balance and recovery practices."
        case 25..<45:
            level = .moderate
            recommendation = "Moderate risk detected. Monitor recovery closely and ensure adequate sleep (7-9h). Avoid consecutive hard days."
        case 45..<65:
            level = .high
            recommendation = "High risk - consider reducing intensity or volume by 20-30% for 3-5 days. Prioritize sleep and easy aerobic work only."
        default:
            level = .veryHigh
            recommendation = "VERY HIGH RISK - Take 1-2 complete rest days immediately. Multiple risk factors present. Resume with easy training only when HRV normalizes."
        }
        
        print("🏥 Injury Risk Assessment:")
        print("   Total Score: \(totalScore)/100")
        print("   Load Risk: \(loadRisk)/40")
        print("   Recovery Risk: \(recoveryRisk)/30")
        print("   Trend Risk: \(trendRisk)/20")
        print("   Monotony Risk: \(monotonyRisk)/10")
        print("   Risk Level: \(level.label)")
        
        return InjuryRiskAssessment(
            riskLevel: level,
            contributingFactors: factors,
            recommendation: recommendation,
            score: min(totalScore, 100),
            loadRisk: loadRisk,
            recoveryRisk: recoveryRisk,
            trendRisk: trendRisk,
            monotonyRisk: monotonyRisk
        )
    }
}
