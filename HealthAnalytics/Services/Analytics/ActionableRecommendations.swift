//
//  ActionableRecommendations.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//  Updated to match new MetricTrend model
//

import Foundation

class ActionableRecommendations {
    
    struct Recommendation: Identifiable {
        let id = UUID()
        let priority: Priority
        let category: Category
        let title: String
        let message: String
        let actionItems: [String]
        
        enum Priority: Int, Comparable {
            case high = 0
            case medium = 1
            case low = 2
            
            static func < (lhs: Priority, rhs: Priority) -> Bool {
                return lhs.rawValue < rhs.rawValue
            }
            
            var emoji: String {
                switch self {
                case .high: return "🔴"
                case .medium: return "🟡"
                case .low: return "🟢"
                }
            }
        }
        
        enum Category {
            case recovery
            case training
            case lifestyle
        }
    }
    
    func generateRecommendations(
        trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?,
        recoveryInsights: [CorrelationEngine.RecoveryInsight],
        trends: [MetricTrend],
        injuryRisk: InjuryRiskCalculator.InjuryRiskAssessment?
    ) -> [Recommendation] {
        
        var recommendations: [Recommendation] = []
        
        // 0. Injury Risk (Highest Priority)
        if let risk = injuryRisk {
            if risk.riskLevel != .low {
                let priority: Recommendation.Priority
                switch risk.riskLevel {
                case .veryHigh, .high: priority = .high
                case .moderate: priority = .medium
                case .low: priority = .low
                }
                
                var actionItems: [String] = ["Risk Factors:"]
                for factor in risk.contributingFactors {
                    actionItems.append(" • \(factor.description)")
                }
                
                actionItems.append("")
                actionItems.append("Recommended Actions:")
                actionItems.append(" • Monitor for pain, soreness, or unusual fatigue")
                actionItems.append(" • Reduce training intensity if symptoms appear")
                actionItems.append(" • Ensure adequate recovery between hard sessions")
                
                recommendations.append(Recommendation(
                    priority: priority,
                    category: .recovery,
                    title: "\(risk.riskLevel.emoji) \(risk.riskLevel.label)",
                    message: risk.recommendation,
                    actionItems: actionItems
                ))
            }
        }
        
        // 1. Check for overtraining/fatigue (integrated with recovery status)
        if let load = trainingLoad {
            // Check actual recovery status from physiological markers
            let isRecovered = checkRecoveryStatus(recoveryInsights: recoveryInsights)
            
            if load.status == .overreaching {
                recommendations.append(Recommendation(
                    priority: .high,
                    category: .recovery,
                    title: "High Overtraining Risk",
                    message: "Your acute:chronic ratio is \(String(format: "%.2f", load.acuteChronicRatio)), indicating high fatigue accumulation.",
                    actionItems: [
                        "Take 2-3 complete rest days this week",
                        "Replace hard workouts with easy recovery sessions",
                        "Prioritize 8+ hours of sleep"
                    ]
                ))
            } else if load.status == .fatigued {
                recommendations.append(Recommendation(
                    priority: .medium,
                    category: .recovery,
                    title: "Elevated Training Load",
                    message: "Your training load is elevated. Monitor recovery closely.",
                    actionItems: [
                        "Add one extra rest day this week",
                        "Keep hard workouts short and focused",
                        "Ensure adequate sleep (7-9 hours)"
                    ]
                ))
            } else if load.status == .fresh {
                // Only show "Well Recovered" if BOTH low training volume AND good recovery markers
                if isRecovered {
                    recommendations.append(Recommendation(
                        priority: .low,
                        category: .training,
                        title: "Well Recovered",
                        message: "Low training load and good recovery markers. Ready for quality training.",
                        actionItems: [
                            "Good time for hard interval sessions",
                            "Consider scheduling a race or time trial",
                            "Gradually increase training volume if desired"
                        ]
                    ))
                } else {
                    // Low volume but poor recovery - don't recommend hard training
                    recommendations.append(Recommendation(
                        priority: .medium,
                        category: .recovery,
                        title: "Low Volume, Poor Recovery",
                        message: "Training load is low but recovery markers indicate fatigue. Prioritize recovery over intensity.",
                        actionItems: [
                            "Focus on easy, short sessions",
                            "Prioritize sleep and nutrition",
                            "Monitor for illness or excessive stress"
                        ]
                    ))
                }
            }
        }
        
        // 2. Check recovery metrics (from CorrelationEngine)
        // Note: Assuming RecoveryInsight structure hasn't changed.
        // If RecoveryInsight.metric is a string, this logic holds.
        let rhrInsight = recoveryInsights.first { $0.metric == "Resting Heart Rate" }
        let hrvInsight = recoveryInsights.first { $0.metric == "Heart Rate Variability" }
        
        if let rhr = rhrInsight, rhr.trend == .fatigued,
           let hrv = hrvInsight, hrv.trend == .fatigued {
            recommendations.append(Recommendation(
                priority: .high,
                category: .recovery,
                title: "Poor Recovery Status",
                message: "Both RHR and HRV indicate inadequate recovery.",
                actionItems: [
                    "Take at least one complete rest day",
                    "Review recent training intensity",
                    "Check for life stressors"
                ]
            ))
        }
        
        // 3. Check for declining trends (Updated for new MetricTrend)
        let decliningTrends = trends.filter { $0.status == .declining || $0.status == .warning }
        
        if decliningTrends.count >= 2 {
            let metrics = decliningTrends.map { $0.metricName }.joined(separator: ", ")
            recommendations.append(Recommendation(
                priority: .medium,
                category: .lifestyle,
                title: "Multiple Declining Metrics",
                message: "\(metrics) are all declining.",
                actionItems: [
                    "Review recent lifestyle changes",
                    "Assess sleep quality and consistency",
                    "Consider stress management techniques"
                ]
            ))
        }
        
        // 4. Check for sleep issues (Updated)
        if let sleepTrend = trends.first(where: { $0.metricName == "Sleep Duration" }),
           sleepTrend.status == .declining || sleepTrend.status == .warning {
            
            let msg = "Your sleep duration is trending negatively (\(sleepTrend.context))."
            
            recommendations.append(Recommendation(
                priority: .medium,
                category: .lifestyle,
                title: "Sleep Duration Declining",
                message: msg,
                actionItems: [
                    "Set a consistent bedtime",
                    "Reduce screen time before bed",
                    "Create a cool, dark sleep environment"
                ]
            ))
        }
        
        // 5. Positive reinforcement (Updated)
        let improvingTrends = trends.filter { $0.status == .improving }
        if improvingTrends.count >= 2 {
            let metrics = improvingTrends.map { $0.metricName }.joined(separator: ", ")
            recommendations.append(Recommendation(
                priority: .low,
                category: .training,
                title: "Positive Progress",
                message: "\(metrics) are improving - great work!",
                actionItems: [
                    "Keep doing what you're doing",
                    "Document what's working well",
                    "Consider gradually progressing training"
                ]
            ))
        }
        
        return recommendations.sorted { $0.priority < $1.priority }
    }
    
    // MARK: - Helper Functions
    
    /// Checks if user is actually recovered based on physiological markers (HRV, RHR)
    /// Returns true if recovery markers are good, false if showing signs of fatigue
    private func checkRecoveryStatus(recoveryInsights: [CorrelationEngine.RecoveryInsight]) -> Bool {
        guard !recoveryInsights.isEmpty else { return true }
        
        // Count how many metrics show fatigue or recovering status
        let fatigueMarkers = recoveryInsights.filter { insight in
            insight.trend == .fatigued || insight.trend == .recovering
        }
        
        // If more than half of recovery metrics show fatigue, not truly recovered
        return fatigueMarkers.count < (recoveryInsights.count / 2)
    }
}
