//
//  MasterCoachEngine.swift
//  HealthAnalytics
//
//  Phase 5: The unified "Master Coach" generative AI engine.
//

import Foundation

struct MasterCoachEngine {

    /// What the illness log says about today. Logged by the user, so it outranks every
    /// signal the app infers: being sick means rest, whatever the recovery score says.
    enum IllnessState: Equatable {
        case none
        /// An open illness; `since` is its first sick day.
        case sick(since: Date)
        /// The illness has ended and its last sick day was at most `recoveringDays` days ago.
        case recovering

        /// How many complete days after the last sick day still count as recovering.
        static let recoveringDays = 2

        static func from(_ spells: [(start: Date, end: Date?)], now: Date = Date(),
                         calendar: Calendar = .current) -> IllnessState {
            let today = calendar.startOfDay(for: now)
            if let since = spells.filter({ $0.end == nil && $0.start <= now }).map(\.start).min() {
                return .sick(since: calendar.startOfDay(for: since))
            }
            let lastSickDay = spells.compactMap(\.end).map { calendar.startOfDay(for: $0) }.filter { $0 <= today }.max()
            guard let lastSickDay else { return .none }
            // An ended illness is over, even when its last day is today ("I'm better" on day one).
            let daysSince = calendar.dateComponents([.day], from: lastSickDay, to: today).day ?? .max
            return daysSince <= recoveringDays ? .recovering : .none
        }

        /// Days still recovering, counting today; 0 when not recovering. Same rule as `from`.
        static func recoveringDaysLeft(_ spells: [(start: Date, end: Date?)], now: Date = Date(),
                                       calendar: Calendar = .current) -> Int {
            guard from(spells, now: now, calendar: calendar) == .recovering else { return 0 }
            let today = calendar.startOfDay(for: now)
            guard let lastSickDay = spells.compactMap(\.end).map({ calendar.startOfDay(for: $0) }).filter({ $0 <= today }).max(),
                  let daysSince = calendar.dateComponents([.day], from: lastSickDay, to: today).day
            else { return 0 }
            return recoveringDays - daysSince + 1
        }
    }

    struct StateVector {
        let morningScore: Int
        let currentScore: Int
        let nextDayForecast: String?
        let acwr: Double
        let injuryRisk: InjuryRiskCalculator.RiskLevel
        let activePatterns: [String]
        let memories: [CoachMemoryNote]
        let illness: IllnessState
        /// The plan's word for today. Nil when there is no plan yet; the score bands decide then.
        let todayEffort: ReadinessRepository.ForecastEffort?
        /// Whether the morning started below the rider's own usual. Nil falls back to under 70.
        let startedLow: Bool?

        init(
            morningScore: Int,
            currentScore: Int,
            nextDayForecast: String?,
            acwr: Double,
            injuryRisk: InjuryRiskCalculator.RiskLevel,
            activePatterns: [String] = [],
            memories: [CoachMemoryNote] = [],
            illness: IllnessState = .none,
            todayEffort: ReadinessRepository.ForecastEffort? = nil,
            startedLow: Bool? = nil
        ) {
            self.morningScore = morningScore
            self.currentScore = currentScore
            self.nextDayForecast = nextDayForecast
            self.acwr = acwr
            self.injuryRisk = injuryRisk
            self.activePatterns = activePatterns
            self.memories = memories
            self.illness = illness
            self.todayEffort = todayEffort
            self.startedLow = startedLow
        }
    }

    /// The paragraph while the illness log says the athlete is sick or just recovered, or nil.
    /// Both message paths open with it, ahead of every inferred signal, and drop the training
    /// forecast: tomorrow's "hard effort" is wrong advice for someone who is sick.
    static func illnessMessage(_ illness: IllnessState, memoryNote: String) -> String? {
        switch illness {
        case .none:
            return nil
        case .sick(let since):
            let daysAgo = Calendar.current.dateComponents([.day], from: since, to: Calendar.current.startOfDay(for: Date())).day ?? 0
            // A weekday name past 6 days would point at the wrong week.
            let day = daysAgo == 0 ? "today"
                : daysAgo <= 6 ? "since \(since.formatted(.dateTime.weekday(.wide)))"
                : "since \(since.formatted(.dateTime.month(.wide).day()))"
            return "You logged that you're sick (\(day)). Skip training: rest, fluids and sleep will do more for you than any workout. Once you've had a full day without symptoms, come back with short, easy sessions.\(memoryNote)"
        case .recovering:
            return "You're just back from being sick. Keep the next couple of days easy, even if your recovery score looks good: going hard too soon is how illness comes back.\(memoryNote)"
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
        - Illness: \(state.illness)
        - Today's effort: \(state.todayEffort?.label ?? "Unknown")
        """
        
        // Simulate network delay for LLM processing (1.5 seconds)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        // The prompt is built for a real model; until one is wired in, the paragraph comes from
        // the heuristic, so every coaching sentence exists once (both paths used to carry their
        // own copy of each, and every copy edit had to be made twice).
        _ = prompt
        return generateHeuristicMessage(state: state)
    }

    /// The coaching paragraph. Also the fallback when synthesis fails.
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

        // 0. Logged illness — the athlete told us; overrides every inferred signal
        if let illness = illnessMessage(state.illness, memoryNote: memoryNote) {
            return illness
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
            let startedLow = state.startedLow ?? (state.morningScore < 70)
            let closing: String?
            switch state.todayEffort {
            case .hard: closing = "You still have room for hard work today."
            case .moderate: closing = "You still have room for moderate work today."
            case .easy: closing = "Keep the rest of today easy."
            case .rest: closing = "Rest for the remainder of the day."
            case nil: closing = nil
            }
            if !startedLow && state.currentScore < 50 {
                return "You woke up primed at \(state.morningScore)%, and you used it well. You're down to \(state.currentScore)% now\(closing.map { ". \($0)" } ?? ", so take it easy the rest of the day.")\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            } else if !startedLow {
                return "You woke up at \(state.morningScore)% and put in work. You're at \(state.currentScore)% now. \(closing ?? "Focus on active recovery.")\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            } else {
                return "You started the day fatigued at \(state.morningScore)%, and your recent effort dropped you to \(state.currentScore)%. \(closing ?? "Prioritize deep rest.")\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
            }
        }

        // 3. Injury risk
        if state.injuryRisk == .high || state.injuryRisk == .veryHigh {
            let instruction: String
            switch state.todayEffort {
            case .hard, .moderate: instruction = "Keep today moderate, with no hard sessions."
            case .easy: instruction = "Keep today easy."
            case .rest: instruction = "Take today off."
            case nil: instruction = "Swap hard sessions for easy aerobic work."
            }
            return "You're \(state.currentScore)% recovered, but injury risk is elevated from load spikes. \(instruction)\(sleepNote)\(forecastText)\(memoryNote)"
        }

        // 4. Baseline readiness — performance windows upgrade the message
        let isPeaking = patterns.contains("performancePeak")
        let isTapering = patterns.contains("tapering")

        // The plan's word decides when there is one: "good" is relative to this rider's normal.
        // The printed score is the in-day one, so a comparison with the rider's usual doesn't cite it.
        let strongOpening = state.todayEffort == nil ? "Your recovery is excellent (\(state.currentScore)%)" : "Your recovery is high for you"
        let solidOpening = state.todayEffort == nil ? "Your recovery is solid (\(state.currentScore)%)" : "You're \(state.currentScore)% recovered"
        let isStrong = state.todayEffort.map { $0 == .hard } ?? (state.currentScore >= 80)
        let isSolid = state.todayEffort.map { $0 == .moderate } ?? (state.currentScore >= 60)

        if isStrong {
            if isPeaking {
                return "\(strongOpening) and your pattern engine shows you're in a peak form window — ideal timing for a race or benchmark effort.\(forecastText)\(memoryNote)"
            }
            if isTapering {
                return "\(strongOpening) and your training volume is down with HRV trending up. If you're tapering for an event, that's exactly the shape you want.\(forecastText)\(memoryNote)"
            }
            return "\(strongOpening). You're ready for intensity today.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        } else if isSolid {
            if isPeaking {
                return "\(solidOpening) and your training data shows a peak form window forming — consider a quality session today.\(loadNote)\(forecastText)\(memoryNote)"
            }
            if isTapering {
                return "\(solidOpening) and your training volume is down with HRV recovering. If this is a planned taper, hold intensity and keep volume low — and if it wasn't, you're not losing the fitness you built.\(loadNote)\(forecastText)\(memoryNote)"
            }
            return "You're \(state.currentScore)% recovered — enough for moderate work, but listen to your body.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        } else if state.todayEffort == .easy {
            return "You're \(state.currentScore)% recovered. Keep today easy.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        } else {
            let opening = state.todayEffort == .rest
                ? "Your recovery is well below your usual."
                : "Your recovery is suppressed (\(state.currentScore)%)."
            return "\(opening) Prioritize rest to bounce back.\(loadNote)\(sleepNote)\(forecastText)\(memoryNote)"
        }
    }
}
