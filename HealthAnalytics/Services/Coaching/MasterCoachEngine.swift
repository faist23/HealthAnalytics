//
//  MasterCoachEngine.swift
//  HealthAnalytics
//
//  Phase 3: The unified "Master Coach" heuristic engine.
//

import Foundation

struct MasterCoachEngine {
    
    struct StateVector {
        let morningScore: Int
        let currentScore: Int
        let nextDayForecast: String? // e.g., "Rest recommended", "Hard effort OK"
        let acwr: Double
        let injuryRisk: String // e.g. "High", "Moderate", "Low"
    }
    
    static func generateMessage(state: StateVector) -> String {
        let delta = state.morningScore - state.currentScore
        let isFatiguedIntraday = delta >= 5
        
        var forecastText = ""
        if let forecast = state.nextDayForecast {
            let lower = forecast.lowercased()
            if lower.contains("rest") {
                forecastText = " Based on your 7-day forecast, you're on track for a rest day tomorrow."
            } else if lower.contains("hard") {
                forecastText = " Based on your 7-day forecast, you'll be primed for a hard effort tomorrow."
            } else if lower.contains("moderate") {
                forecastText = " Based on your 7-day forecast, expect moderate training tomorrow."
            } else if lower.contains("easy") {
                forecastText = " Based on your 7-day forecast, plan for an easy day tomorrow."
            } else {
                forecastText = " Based on your 7-day forecast, you're on track for \(lower) tomorrow."
            }
        }
        
        if isFatiguedIntraday {
            if state.morningScore >= 70 && state.currentScore < 50 {
                return "You woke up primed at \(state.morningScore)%, and you used it well. Your current readiness is \(state.currentScore)%, so take it easy the rest of the day.\(forecastText)"
            } else if state.morningScore >= 70 && state.currentScore >= 50 {
                return "You woke up at \(state.morningScore)% and put in work. Your current readiness is \(state.currentScore)%. Focus on active recovery now.\(forecastText)"
            } else if state.morningScore < 70 {
                return "You started the day fatigued at \(state.morningScore)%, and your recent effort dropped your readiness to \(state.currentScore)%. Prioritize deep rest now.\(forecastText)"
            }
        }
        
        // No significant workout today
        if state.injuryRisk == "High" || state.injuryRisk == "Very High" {
            return "Your readiness is \(state.currentScore)%, but your injury risk is elevated due to load spikes. Play it safe: swap hard sessions for easy aerobic work.\(forecastText)"
        }
        
        if state.currentScore >= 80 {
            return "Your readiness is excellent (\(state.currentScore)%). Your nervous system is primed for intensity today.\(forecastText)"
        } else if state.currentScore >= 60 {
            return "Your readiness is stable (\(state.currentScore)%). You can take on moderate training, but listen to your body.\(forecastText)"
        } else {
            return "Your readiness is suppressed (\(state.currentScore)%). Prioritize rest and recovery to bounce back.\(forecastText)"
        }
    }
}
