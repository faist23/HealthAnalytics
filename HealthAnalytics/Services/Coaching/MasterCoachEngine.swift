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
        let nextDayForecast: String?
        let acwr: Double
        let injuryRisk: String
        let activePatterns: [String]
        let memories: [CoachMemoryNote]

        init(
            morningScore: Int,
            currentScore: Int,
            nextDayForecast: String?,
            acwr: Double,
            injuryRisk: String,
            activePatterns: [String] = [],
            memories: [CoachMemoryNote] = []
        ) {
            self.morningScore = morningScore
            self.currentScore = currentScore
            self.nextDayForecast = nextDayForecast
            self.acwr = acwr
            self.injuryRisk = injuryRisk
            self.activePatterns = activePatterns
            self.memories = memories
        }
    }

    static func generateMessage(state: StateVector) -> String {
        let delta = state.morningScore - state.currentScore
        let isFatiguedIntraday = delta >= 5

        // Forecast suffix
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

        let patterns = state.activePatterns
        
        let activeMemories = state.memories.filter { $0.isCurrentlyActive }
        var memoryNote = ""
        if !activeMemories.isEmpty {
            let contextStrings = activeMemories.map { $0.context }.joined(separator: ", ")
            memoryNote = " Keeping in mind: \(contextStrings)."
        }

        // 1. Health alarm — overrides all other signals
        if patterns.contains("hrvPrecursor") {
            return "Your HRV has shown an early warning pattern. Dial back intensity today and prioritize sleep — your body may be fighting something.\(forecastText)\(memoryNote)"
        }

        // Load and sleep qualifiers (appended to the main sentence when relevant)
        var loadNote = ""
        if patterns.contains("backToBackCrash") {
            loadNote = " Your pattern data shows back-to-back hard sessions hit you harder than average — protect tomorrow."
        } else if patterns.contains("blockCrashCycle") {
            loadNote = " You tend to crash at the end of training blocks — watch for fatigue signals as this block progresses."
        }

        var sleepNote = ""
        if patterns.contains("sleepFragmentation") {
            sleepNote = " Sleep quality has been fragmenting under your current load — prioritize sleep hygiene tonight."
        }

        // 2. Intraday fatigue branch
        if isFatiguedIntraday {
            if state.morningScore >= 70 && state.currentScore < 50 {
                return "You woke up primed at \(state.morningScore)%, and you used it well. Current readiness is \(state.currentScore)%, so take it easy the rest of the day.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            } else if state.morningScore >= 70 && state.currentScore >= 50 {
                return "You woke up at \(state.morningScore)% and put in work. Current readiness is \(state.currentScore)%. Focus on active recovery now.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            } else {
                return "You started the day fatigued at \(state.morningScore)%, and your recent effort dropped readiness to \(state.currentScore)%. Prioritize deep rest.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            }
        }

        // 3. Injury risk
        if state.injuryRisk == "High" || state.injuryRisk == "Very High" {
            return "Your readiness is \(state.currentScore)%, but injury risk is elevated from load spikes. Swap hard sessions for easy aerobic work.\(sleepNote)\(forecastText)\(memoryNote)"
        }

        // 4. Baseline readiness — performance windows upgrade the message
        let isPeaking = patterns.contains("performancePeak")
        let isTapering = patterns.contains("tapering")

        if state.currentScore >= 80 {
            if isPeaking {
                return "Your readiness is excellent (\(state.currentScore)%) and your pattern engine shows you're in a peak form window — ideal timing for a race or benchmark effort.\(forecastText)\(memoryNote)"
            }
            if isTapering {
                return "Your readiness is excellent (\(state.currentScore)%) and your load is tapering with HRV trending up. Trust the process — your peak window is approaching.\(forecastText)\(memoryNote)"
            }
            return "Your readiness is excellent (\(state.currentScore)%). Your nervous system is primed for intensity today.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        } else if state.currentScore >= 60 {
            if isPeaking {
                return "Your readiness is solid (\(state.currentScore)%) and your training data shows a peak form window forming — consider a quality session today.\(loadNote)\(forecastText)\(memoryNote)"
            }
            if isTapering {
                return "Your readiness is solid (\(state.currentScore)%) and your taper is underway. Keep intensity but cut volume — fitness is locked in.\(loadNote)\(forecastText)\(memoryNote)"
            }
            return "Your readiness is stable (\(state.currentScore)%). You can take on moderate training, but listen to your body.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        } else {
            return "Your readiness is suppressed (\(state.currentScore)%). Prioritize rest and recovery to bounce back.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        }
    }
}
