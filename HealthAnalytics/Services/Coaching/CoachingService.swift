//
//  CoachingService.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/2/26.
//


import Foundation
import SwiftUI

/// Logic layer that translates raw data into athlete-facing coaching instructions.
struct CoachingService {
    
    enum DailyStatus {
        case perform  // High readiness, optimal load
        case baseline // Normal training
        case recover  // High fatigue or low recovery signals
        
        var color: Color {
            switch self {
            case .perform: return .green
            case .baseline: return .blue
            case .recover: return .orange
            }
        }
    }
    
    struct DailyInstruction {
        let status: DailyStatus
        let headline: String
        let subline: String
        let primaryInsight: String?
        let targetAction: String? // New: Specific goal for the session
    }

    func generateDailyInstruction(
        readiness: PredictiveReadinessService.ReadinessAssessment,
        insights: [CorrelationEngine.ActivityTypeInsight],
        recovery: [CorrelationEngine.RecoveryInsight],
        prediction: PerformancePredictor.Prediction? // New: Pass the ML result here
    ) -> DailyInstruction{
        
        // 1. Determine Status based on ACWR (Existing logic: 0.8 - 1.3 is optimal)
        let status: DailyStatus
        if readiness.acwr > 1.3 || recovery.contains(where: { $0.trend == .fatigued }) {
            status = .recover
        } else if readiness.acwr >= 0.8 && readiness.acwr <= 1.3 {
            status = .perform
        } else {
            status = .baseline
        }
        
        // 2. Draft athlete-facing headlines
        let headline: String
        let subline: String
        
        switch status {
        case .perform:
            headline = "Ready to Perform"
            subline = "Your training load and recovery are in sync. Today is a great day for intensity."
        case .recover:
            headline = "Focus on Recovery"
            subline = "Fatigue signals are elevated. Consider a rest day or very light activity."
        case .baseline:
            headline = "Building Base"
            subline = "Your load is low. Focus on consistent, steady-state movement today."
        }
        
        // 3. Select the most actionable insight from the CorrelationEngine
        // We filter for significant differences you've seen in logs (>5%)
        let topInsight = insights.first(where: { abs($0.percentDifference) > 5.0 })
        let insightText = topInsight.map { 
            "Coach's Tip: You perform \(String(format: "%.0f", abs($0.percentDifference)))% better on \($0.activityType)s after 7+ hours of sleep." 
        }
    
        var target: String? = nil
        if let pred = prediction, status == .perform {
            target = "Target for today: Aim for an average of \(String(format: "%.0f", pred.predictedPerformance)) \(pred.unit) on your \(pred.activityType)."
        } else if status == .recover {
            target = "Target for today: Keep heart rate below Zone 2 or take a complete rest day."
        }
        
        return DailyInstruction(
            status: status,
            headline: headline,
            subline: subline,
            primaryInsight: insightText,
            targetAction: target
        )
    }
}
