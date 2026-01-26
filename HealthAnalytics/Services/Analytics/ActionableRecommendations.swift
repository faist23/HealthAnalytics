//
//  ActionableRecommendations.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import Foundation

struct ActionableRecommendations {
    
    struct Recommendation {
        let priority: Priority
        let category: Category
        let title: String
        let message: String
        let actionItems: [String]
        
        enum Priority {
            case high
            case medium
            case low
            
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
    
    /// Generates actionable recommendations based on all available insights
    func generateRecommendations(
        trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?,
        recoveryInsights: [CorrelationEngine.RecoveryInsight],
        trends: [TrendDetector.MetricTrend]
    ) -> [Recommendation] {
        
        var recommendations: [Recommendation] = []
        
        // 1. Check for overtraining/fatigue
        if let load = trainingLoad {
            if load.status == .overreaching {
                recommendations.append(Recommendation(
                    priority: .high,
                    category: .recovery,
                    title: "High Overtraining Risk",
                    message: "Your acute:chronic ratio is \(String(format: "%.2f", load.acuteChronicRatio)), indicating high fatigue accumulation.",
                    actionItems: [
                        "Take 2-3 complete rest days this week",
                        "Replace hard workouts with easy recovery sessions",
                        "Prioritize 8+ hours of sleep",
                        "Consider getting a massage or other recovery modalities"
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
                        "Ensure adequate sleep (7-9 hours)",
                        "Monitor resting HR and HRV trends"
                    ]
                ))
            } else if load.status == .fresh {
                recommendations.append(Recommendation(
                    priority: .low,
                    category: .training,
                    title: "Well Recovered",
                    message: "You're well-rested and ready for quality training.",
                    actionItems: [
                        "Good time for hard interval sessions",
                        "Consider scheduling a race or time trial",
                        "Gradually increase training volume if desired",
                        "Maintain current recovery practices"
                    ]
                ))
            }
        }
        
        // 2. Check recovery metrics
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
                    "Check for life stressors (work, travel, illness)",
                    "Ensure proper nutrition and hydration"
                ]
            ))
        }
        
        // 3. Check for declining trends
        let decliningTrends = trends.filter { $0.direction == .declining }
        
        if decliningTrends.count >= 2 {
            let metrics = decliningTrends.map { $0.metric }.joined(separator: ", ")
            recommendations.append(Recommendation(
                priority: .medium,
                category: .lifestyle,
                title: "Multiple Declining Metrics",
                message: "\(metrics) are all declining.",
                actionItems: [
                    "Review recent lifestyle changes",
                    "Assess sleep quality and consistency",
                    "Consider stress management techniques",
                    "Evaluate training-to-recovery balance"
                ]
            ))
        }
        
        // 4. Check for sleep issues
        if let sleepTrend = trends.first(where: { $0.metric == "Sleep Duration" }),
           sleepTrend.direction == .declining {
            recommendations.append(Recommendation(
                priority: .medium,
                category: .lifestyle,
                title: "Sleep Duration Declining",
                message: sleepTrend.message,
                actionItems: [
                    "Set a consistent bedtime",
                    "Reduce screen time before bed",
                    "Create a cool, dark sleep environment",
                    "Limit caffeine after 2 PM"
                ]
            ))
        }
        
        // 5. Positive reinforcement for improving trends
        let improvingTrends = trends.filter { $0.direction == .improving }
        if improvingTrends.count >= 2 {
            let metrics = improvingTrends.map { $0.metric }.joined(separator: ", ")
            recommendations.append(Recommendation(
                priority: .low,
                category: .training,
                title: "Positive Progress",
                message: "\(metrics) are improving - great work!",
                actionItems: [
                    "Keep doing what you're doing",
                    "Document what's working well",
                    "Consider gradually progressing training",
                    "Maintain current recovery habits"
                ]
            ))
        }
        
        return recommendations.sorted { $0.priority.hashValue < $1.priority.hashValue }
    }
}

// Make Priority hashable for sorting
extension ActionableRecommendations.Recommendation.Priority: Hashable {
    var hashValue: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}