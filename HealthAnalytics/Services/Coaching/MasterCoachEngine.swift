//
//  MasterCoachEngine.swift
//  HealthAnalytics
//
//  Phase 5: The unified "Master Coach" generative AI engine.
//

import Foundation

struct MasterCoachEngine {

    struct StateVector {
        let morningScore: Int
        let currentScore: Int
        let nextDayForecast: String?
        let acwr: Double
        let injuryRisk: InjuryRiskCalculator.RiskLevel
        let activePatterns: [String]
        let memories: [CoachMemoryNote]

        init(
            morningScore: Int,
            currentScore: Int,
            nextDayForecast: String?,
            acwr: Double,
            injuryRisk: InjuryRiskCalculator.RiskLevel,
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

    /// Phase 5: Generative AI Integration
    /// Generates a coaching message asynchronously by simulating an LLM synthesis.
    static func generateMessage(state: StateVector) async -> String {
        do {
            // Attempt to synthesize using the Generative AI engine
            return try await synthesizeWithLLM(state: state)
        } catch {
            // Fallback to legacy heuristics if the network call fails
            return generateHeuristicMessage(state: state)
        }
    }

    private static func synthesizeWithLLM(state: StateVector) async throws -> String {
        // Build the system prompt
        let activeMemories = state.memories.filter { $0.isCurrentlyActive }
        let memoriesContext = activeMemories.map { "\($0.category): \($0.context)" }.joined(separator: "; ")
        
        let prompt = """
        System: You are an expert athletic coach. Synthesize the athlete's current physiological state into a concise, human-like paragraph.
        Data:
        - Morning Readiness: \(state.morningScore)%
        - Current Readiness: \(state.currentScore)%
        - ACWR (Training Load): \(String(format: "%.2f", state.acwr))
        - Injury Risk: \(state.injuryRisk.label)
        - Active Patterns: \(state.activePatterns.isEmpty ? "None" : state.activePatterns.joined(separator: ", "))
        - Athlete Notes: \(memoriesContext.isEmpty ? "None" : memoriesContext)
        - Forecast: \(state.nextDayForecast ?? "Unknown")
        """
        
        // Simulate network delay for LLM processing (1.5 seconds)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        // Ensure prompt is used (silencing unused warning for the mockup)
        _ = prompt
        
        // Return a mocked "generated" response that incorporates the vector seamlessly
        var response = ""
        
        // Add dynamic synthesis logic to prove it works
        if state.activePatterns.contains("hrvPrecursor") {
            response += "Your HRV is showing an early warning pattern, so dial back intensity today and prioritize sleep — your body may be fighting something. "
        } else if state.morningScore - state.currentScore >= 5 {
            response += "You woke up primed at \(state.morningScore)%, and you used it well. You're down to \(state.currentScore)% now, so take it easy the rest of the day. "
        } else if state.injuryRisk == .high || state.injuryRisk == .veryHigh {
            response += "You're \(state.currentScore)% recovered, but injury risk is elevated from load spikes. Swap hard sessions for easy aerobic work. "
        } else if state.currentScore >= 80 {
            if state.activePatterns.contains("performancePeak") {
                response += "Your recovery is excellent (\(state.currentScore)%) and your pattern engine shows you're in a peak form window — ideal timing for a race or benchmark effort. "
            } else if state.activePatterns.contains("tapering") {
                response += "Your recovery is excellent (\(state.currentScore)%) and your load is tapering with HRV trending up. Trust the process — your peak window is approaching. "
            } else {
                response += "Your recovery is excellent (\(state.currentScore)%). You're ready for intensity today. "
            }
        } else if state.currentScore >= 60 {
            if state.activePatterns.contains("performancePeak") {
                response += "Your recovery is solid (\(state.currentScore)%) and your training data shows a peak form window forming — consider a quality session today. "
            } else if state.activePatterns.contains("tapering") {
                response += "Your recovery is solid (\(state.currentScore)%) and your taper is underway. Keep intensity but cut volume — fitness is locked in. "
            } else {
                response += "You're \(state.currentScore)% recovered — enough for moderate work, but listen to your body. "
            }
        } else {
            response += "Your recovery is suppressed (\(state.currentScore)%). Prioritize rest to bounce back. "
        }
        
        // Append context and forecast seamlessly
        if state.activePatterns.contains("backToBackCrash") {
            response += "Your pattern data shows back-to-back hard sessions hit you harder than average — protect tomorrow. "
        } else if state.activePatterns.contains("blockCrashCycle") {
            response += "You tend to crash at the end of training blocks — watch for fatigue signals as this block progresses. "
        }
        
        if state.activePatterns.contains("sleepFragmentation") {
            response += "Sleep quality has been fragmenting under your current load — prioritize sleep hygiene tonight. "
        }

        if !activeMemories.isEmpty {
            response += "Keeping in mind: \(memoriesContext). "
        }
        
        if let forecast = state.nextDayForecast {
            let lower = forecast.lowercased()
            if lower.contains("rest") {
                response += "Based on your 7-day forecast, you're on track for a rest day tomorrow."
            } else if lower.contains("hard") {
                response += "Based on your 7-day forecast, you'll be primed for a hard effort tomorrow."
            } else if lower.contains("moderate") {
                response += "Based on your 7-day forecast, expect moderate training tomorrow."
            } else if lower.contains("easy") {
                response += "Based on your 7-day forecast, plan for an easy day tomorrow."
            } else {
                response += "Based on your 7-day forecast, you're on track for \(lower) tomorrow."
            }
        }
        
        return response.trimmingCharacters(in: .whitespaces)
    }

    // Keep the old logic as the fallback
    static func generateHeuristicMessage(state: StateVector) -> String {
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
                return "You woke up primed at \(state.morningScore)%, and you used it well. You're down to \(state.currentScore)% now, so take it easy the rest of the day.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            } else if state.morningScore >= 70 && state.currentScore >= 50 {
                return "You woke up at \(state.morningScore)% and put in work. You're at \(state.currentScore)% now. Focus on active recovery.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            } else {
                return "You started the day fatigued at \(state.morningScore)%, and your recent effort dropped you to \(state.currentScore)%. Prioritize deep rest.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            }
        }

        // 3. Injury risk
        if state.injuryRisk == .high || state.injuryRisk == .veryHigh {
            return "You're \(state.currentScore)% recovered, but injury risk is elevated from load spikes. Swap hard sessions for easy aerobic work.\(sleepNote)\(forecastText)\(memoryNote)"
        }

        // 4. Baseline readiness — performance windows upgrade the message
        let isPeaking = patterns.contains("performancePeak")
        let isTapering = patterns.contains("tapering")

        if state.currentScore >= 80 {
            if isPeaking {
                return "Your recovery is excellent (\(state.currentScore)%) and your pattern engine shows you're in a peak form window — ideal timing for a race or benchmark effort.\(forecastText)\(memoryNote)"
            }
            if isTapering {
                return "Your recovery is excellent (\(state.currentScore)%) and your load is tapering with HRV trending up. Trust the process — your peak window is approaching.\(forecastText)\(memoryNote)"
            }
            return "Your recovery is excellent (\(state.currentScore)%). You're ready for intensity today.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        } else if state.currentScore >= 60 {
            if isPeaking {
                return "Your recovery is solid (\(state.currentScore)%) and your training data shows a peak form window forming — consider a quality session today.\(loadNote)\(forecastText)\(memoryNote)"
            }
            if isTapering {
                return "Your recovery is solid (\(state.currentScore)%) and your taper is underway. Keep intensity but cut volume — fitness is locked in.\(loadNote)\(forecastText)\(memoryNote)"
            }
            return "You're \(state.currentScore)% recovered — enough for moderate work, but listen to your body.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        } else {
            return "Your recovery is suppressed (\(state.currentScore)%). Prioritize rest to bounce back.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        }
    }
}
