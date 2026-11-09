//
//  ForecastPlanner.swift
//  HealthAnalytics
//
//  The 7-day forecast as a personal plan: the hardest effort the rider can absorb each day,
//  judged against their own normal and assuming they followed the plan on the days before.
//  Pure: everything comes in as values, so a rider's week can be tested without a store.
//

import Foundation

/// One complete day of history. A nil score means no score row: unknown, never rest.
struct ForecastHistoryDay: Equatable {
    let date: Date
    let score: Int?
    let load: Double
}

/// What the rider's history says about them. All scores are read in units of `spread` from `normal`.
struct ForecastProfile: Equatable {
    typealias Effort = ReadinessRepository.ForecastEffort

    static let minimumScoredDays = 14
    static let normalWindowDays = 28
    static let trainingWindowDays = 90
    static let spreadFloor = 4.0
    /// MAD to standard-deviation scale for normally distributed scores.
    static let madScale = 1.4826

    static let hardEdge = 0.2
    static let moderateEdge = -0.5
    static let easyEdge = -1.5

    /// `dailyLoad >= 1.0` is the app's existing line for a training day.
    static let trainingDayLoad = 1.0
    static let minimumTrainingDays = 8
    /// A hard day must stand clear of the median, or a rider whose rides are all alike
    /// would count every ride as hard and never be offered a Hard day.
    static let hardMedianMultiple = 1.25
    static let fallbackHardLoad = 3.0
    static let fallbackModerateLoad = 1.5
    static let fallbackEasyLoad = 0.75

    static let minimumEpisodes = 4
    static let returnWindowDays = 5
    static let defaultRecoveryDays = 1
    static let maximumRecoveryDays = 3
    static let defaultDip = 1.0
    static let dipRange = 0.5...2.0

    /// Next-day lift in spreads. The rider's normal already includes the cost of their hard
    /// days, so any non-hard day repays some of it. A Hard day costs `dip` instead.
    static let restLift = 1.0
    static let easyLift = 0.7
    static let moderateLift = 0.35

    let normal: Double
    let spread: Double
    let hardLoad: Double
    let moderateLoad: Double
    let easyLoad: Double
    /// How far (in spreads) the next morning falls after a hard day.
    let dip: Double
    /// How many days after a hard day stay below Hard. Never under 1 in this release.
    let recoveryDays: Int
    let episodeCount: Int
    /// How often this rider actually trains (last 28 days). The plan's assumed days count at this
    /// share toward projected ACWR, or a three-rides-a-week rider's own plan reads as a load ramp.
    var trainingDayShare = 1.0

    /// `history` is ascending complete days, ending before `today`. Nil below the 14-score minimum.
    static func learn(history: [ForecastHistoryDay], today: Date, calendar: Calendar) -> ForecastProfile? {
        let start = calendar.startOfDay(for: today)
        guard let normalStart = calendar.date(byAdding: .day, value: -normalWindowDays, to: start),
              let trainingStart = calendar.date(byAdding: .day, value: -trainingWindowDays, to: start)
        else { return nil }
        let complete = history.filter { $0.date < start }

        let scores = complete.filter { $0.date >= normalStart }.compactMap(\.score).map(Double.init)
        guard scores.count >= minimumScoredDays, let normal = median(scores) else { return nil }
        let mad = median(scores.map { abs($0 - normal) }) ?? 0
        let spread = max(madScale * mad, spreadFloor)

        let inWindow = complete.filter { $0.date >= trainingStart }
        let trainingLoads = inWindow.map(\.load).filter { $0 >= trainingDayLoad }
        var hardLoad = fallbackHardLoad, moderateLoad = fallbackModerateLoad, easyLoad = fallbackEasyLoad
        if trainingLoads.count >= minimumTrainingDays, let med = median(trainingLoads) {
            hardLoad = max(percentile(trainingLoads, 0.75), hardMedianMultiple * med, trainingDayLoad)
            moderateLoad = min(med, hardLoad)
            easyLoad = min(percentile(trainingLoads, 0.25), moderateLoad)
        }

        let found = episodes(in: inWindow, normal: normal, spread: spread, hardLoad: hardLoad, calendar: calendar)
        var recoveryDays = defaultRecoveryDays, dip = defaultDip
        if found.count >= minimumEpisodes {
            let medianDays = median(found.map { Double($0.daysBelow) }) ?? 1
            recoveryDays = min(max(Int(medianDays.rounded(.up)), defaultRecoveryDays), maximumRecoveryDays)
            let medianDip = median(found.map(\.dip)) ?? defaultDip
            dip = min(max(medianDip, dipRange.lowerBound), dipRange.upperBound)
        }

        let trainingDays = complete.filter { $0.date >= normalStart && $0.load >= trainingDayLoad }.count
        return ForecastProfile(normal: normal, spread: spread, hardLoad: hardLoad, moderateLoad: moderateLoad,
                               easyLoad: easyLoad, dip: dip, recoveryDays: recoveryDays, episodeCount: found.count,
                               trainingDayShare: Double(trainingDays) / Double(normalWindowDays))
    }

    /// A hard day with non-hard days on both sides, a score the next morning, and an outcome
    /// we can see: back within the window, or the whole window spent below normal.
    private static func episodes(in days: [ForecastHistoryDay], normal: Double, spread: Double, hardLoad: Double,
                                 calendar: Calendar) -> [(daysBelow: Int, dip: Double)] {
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { $1 })
        func at(_ date: Date, _ offset: Int) -> ForecastHistoryDay? {
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)).flatMap { byDay[$0] }
        }
        return days.compactMap { hard in
            guard hard.load >= hardLoad,
                  (at(hard.date, -1)?.load ?? 0) < hardLoad,
                  let next = at(hard.date, 1), next.load < hardLoad, let nextScore = next.score
            else { return nil }
            for offset in 1...returnWindowDays {
                guard let morning = at(hard.date, offset) else { return nil }
                if morning.load >= hardLoad { return nil }
                if let score = morning.score, (Double(score) - normal) / spread >= moderateEdge {
                    return (daysBelow: offset - 1, dip: (normal - Double(nextScore)) / spread)
                }
            }
            return (daysBelow: returnWindowDays, dip: (normal - Double(nextScore)) / spread)
        }
    }

    func z(_ score: Double) -> Double { (score - normal) / spread }

    func band(z: Double) -> Effort {
        if z >= Self.hardEdge { return .hard }
        if z >= Self.moderateEdge { return .moderate }
        if z >= Self.easyEdge { return .easy }
        return .rest
    }

    /// How much of a day's distance from normal is left the next morning.
    var rho: Double {
        switch recoveryDays {
        case ...1: return 0.4
        case 2: return 0.6
        default: return 0.75
        }
    }

    func typicalLoad(_ effort: Effort) -> Double {
        switch effort {
        case .hard: return hardLoad
        case .moderate: return moderateLoad
        case .easy: return easyLoad
        case .rest: return 0
        }
    }

    /// Next-day lift for a planned effort.
    func lift(_ effort: Effort) -> Double {
        switch effort {
        case .hard: return -dip
        case .moderate: return Self.moderateLift
        case .easy: return Self.easyLift
        case .rest: return Self.restLift
        }
    }

    /// Next-day lift for an actual load: a rest day's lift at zero, a Hard day's cost at `hardLoad`.
    func rideEffect(load: Double) -> Double {
        Self.restLift - (Self.restLift + dip) * load / hardLoad
    }

    func isHard(load: Double) -> Bool { load >= hardLoad }

    // MARK: - Statistics

    static func median(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : percentile(values, 0.5)
    }

    /// Linear interpolation between closest ranks.
    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
}

/// A built plan, and the profile it was judged against.
struct ForecastPlan {
    let days: [ReadinessRepository.ReadinessForecastDay]
    let profile: ForecastProfile
}

enum ForecastIllness: Equatable {
    case none
    case sick
    /// `daysLeft` counts today.
    case recovering(daysLeft: Int)
}

/// An active Coach note's limit on the plan. A nil `until` caps every day until it is cleared.
struct ForecastNoteCap: Equatable {
    let cap: ReadinessRepository.ForecastEffort
    let reason: String
    let until: Date?
}

struct ForecastPlanInput {
    let now: Date
    /// Ignores today's rides. Where the stepping into tomorrow starts, so a ride isn't counted twice.
    let startScore: Int
    /// On the stored rows' scale, less today's workout and step fatigue. Decides today's word.
    let currentScore: Int
    /// Load of the workouts stored so far today.
    let rodeLoadToday: Double
    /// Complete days ending yesterday.
    let recentLoads: [ForecastHistoryDay]
    let profile: ForecastProfile
    var illness: ForecastIllness = .none
    var hrvPrecursorActive = false
    var injuryRiskElevated = false
    var noteCaps: [ForecastNoteCap] = []
    var shortSleepNights = 0
    /// Release 2 fills this from the learned illness and crash history. Nil means no cap.
    var hardDaysPerWeekCap: Int? = nil
    /// Day 0 already happened (Forecast Check): its actual load is all it did, not the plan's suggestion.
    var firstDayIsFinished = false
    /// How rides have felt lately against comparable ones, in rating points (`EffortAbsorption.trend`).
    /// Positive means harder than usual. Shifts where tomorrow onward starts; 0 changes nothing.
    var absorptionTrend = 0.0
    /// (window close, planned load by start of day) → ACWR, from the one ACWR engine.
    let projectedACWR: (Date, [Date: Double]) -> Double
}

enum ForecastPlanner {
    typealias Effort = ReadinessRepository.ForecastEffort
    typealias Day = ReadinessRepository.ReadinessForecastDay

    static let horizonDays = 7
    /// Hard-day and HRV warnings describe now, so they hold for today and tomorrow only.
    static let nearTermDays = 2
    /// Under this a workout is a warmup, the same line the sick-day proxy uses.
    static let namedRideLoad = 0.5
    /// Below 4 training days in 28 there is too little chronic load for a ratio to mean anything.
    /// One warmup after a layoff reads as ACWR 4.0 otherwise.
    static let minimumLoadCeilingShare = 4.0 / 28.0

    /// Each day builds on the one before: the day's effort moves the next morning.
    static func plan(_ input: ForecastPlanInput, calendar: Calendar) -> [Day] {
        let profile = input.profile
        let today = calendar.startOfDay(for: input.now)
        var hardDates = input.recentLoads.filter { profile.isHard(load: $0.load) }
            .map { calendar.startOfDay(for: $0.date) }
        var planned: [Date: Double] = [:]
        // How rides feel shifts tomorrow's starting point, at full strength, and the stepping lets
        // it fade (shifting today's start instead would be damped by rho before tomorrow). A twin
        // without the shift tells the reason which days the feel actually moved.
        let feelShift = EffortAbsorption.zShift(trend: input.absorptionTrend)
        var z = profile.z(Double(input.startScore))
        var zUnshifted = z
        var previous: Effort?
        var days: [Day] = []

        for offset in 0..<horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)
            else { break }

            let byRecovery = profile.band(z: offset == 0 ? profile.z(Double(input.currentScore)) : z)
            let acwr = profile.trainingDayShare >= minimumLoadCeilingShare
                ? input.projectedACWR(offset == 0 ? input.now : dayEnd, planned)
                : 1.0
            let caps = caps(for: input, offset: offset, date: date, acwr: acwr, hardDates: hardDates, calendar: calendar)
            let binding = caps.max { $0.cap < $1.cap }
            let effort = max(byRecovery, binding?.cap ?? .hard)

            // The feel explains the day only when it changed the word shown: a cap that sets the
            // same word either way keeps its own reason.
            let unshiftedEffort = max(profile.band(z: zUnshifted), binding?.cap ?? .hard)
            let feelMovedDay = offset > 0 && feelShift != 0 && effort != unshiftedEffort
            // A cap explains the day when it is stricter than recovery would be without the feel.
            // When the feel set the word, judge the cap against the shifted band so the feel's reason wins.
            let byRecoveryForReason = offset > 0 && !feelMovedDay ? min(byRecovery, profile.band(z: zUnshifted)) : byRecovery
            days.append(Day(date: date, effort: effort, reason: reason(
                input: input, offset: offset, effort: effort, byRecovery: byRecoveryForReason,
                binding: binding, previous: previous,
                feel: feelMovedDay ? (feelShift < 0 ? "Rides feeling harder than usual" : "Rides feeling easier than usual") : nil)))

            let rode = offset == 0 ? input.rodeLoadToday : 0
            let finished = offset == 0 && input.firstDayIsFinished
            var impulse = finished ? profile.rideEffect(load: rode) : profile.lift(effort)
            if rode > 0 { impulse = min(impulse, profile.rideEffect(load: rode)) }
            z = profile.rho * z + impulse + (offset == 0 ? feelShift : 0)
            zUnshifted = profile.rho * zUnshifted + impulse

            planned[date] = max(0, profile.typicalLoad(effort) * profile.trainingDayShare - rode)
            if (effort == .hard && !finished) || profile.isHard(load: rode) { hardDates.append(date) }
            previous = effort
        }
        return days
    }

    /// Every limit on this day, in the order a tie names its reason.
    private static func caps(for input: ForecastPlanInput, offset: Int, date: Date, acwr: Double,
                             hardDates: [Date], calendar: Calendar) -> [(cap: Effort, reason: String)] {
        var caps: [(cap: Effort, reason: String)] = []

        if offset == 0, input.profile.isHard(load: input.rodeLoadToday) { caps.append((.moderate, "Rode hard today")) }

        switch input.illness {
        case .none: break
        case .sick: caps.append((.rest, illnessSick))
        case .recovering(let daysLeft):
            if offset < daysLeft { caps.append((.easy, illnessRecovering)) }
        }

        for note in input.noteCaps where note.until.map({ date < $0 }) ?? true {
            caps.append((note.cap, note.reason))
        }

        if offset < nearTermDays, input.hrvPrecursorActive { caps.append((.easy, "HRV dipping")) }

        if acwr > 1.5 {
            caps.append((.easy, loadRamping))
        } else if acwr > 1.3 {
            caps.append((.moderate, loadRamping))
        }
        if offset < nearTermDays, input.injuryRiskElevated { caps.append((.moderate, loadRamping)) }

        let lastHard = hardDates.filter { date > $0 }.max()
        if let lastHard,
           let gap = calendar.dateComponents([.day], from: lastHard, to: date).day,
           gap <= input.profile.recoveryDays {
            caps.append((.moderate, "Still recovering from \(lastHard.formatted(.dateTime.weekday(.wide)))"))
        }

        if let weeklyCap = input.hardDaysPerWeekCap,
           let weekStart = calendar.date(byAdding: .day, value: -6, to: date),
           hardDates.filter({ $0 >= weekStart && $0 < date }).count >= weeklyCap {
            caps.append((.moderate, "Enough hard days this week"))
        }
        return caps
    }

    private static let illnessSick = "Sick"
    private static let illnessRecovering = "Easing back after illness"
    private static let loadRamping = "Load ramping fast"

    /// The one fact that best explains the day. Nil when the day is simply what recovery allows.
    private static func reason(input: ForecastPlanInput, offset: Int, effort: Effort, byRecovery: Effort,
                               binding: (cap: Effort, reason: String)?, previous: Effort?,
                               feel: String? = nil) -> String? {
        if let binding, binding.reason == illnessSick || binding.reason == illnessRecovering {
            return binding.reason
        }
        if let binding, binding.cap > byRecovery { return binding.reason }
        if offset == 0 {
            if input.profile.isHard(load: input.rodeLoadToday) { return "Rode hard today" }
            if input.rodeLoadToday >= namedRideLoad { return "Rode today" }
        }
        if offset == 0, effort > .moderate {
            switch input.shortSleepNights {
            case 0: return "Low recovery"
            case 1: return "Short sleep"
            default: return "Two short nights"
            }
        }
        if let feel { return feel }
        // After a ride the word was low from riding, so the next day isn't a bounce back from rest.
        let rodeYesterday = offset == 1 && input.rodeLoadToday >= namedRideLoad
        if let previous, previous >= .easy, effort < previous, !rodeYesterday { return "Bouncing back after rest" }
        return nil
    }
}

/// How the plan would have done on the rider's own past, for Settings → Forecast Check.
struct ForecastCheckResult: Equatable {
    struct Miss: Equatable {
        let date: Date
        let suggested: ReadinessRepository.ForecastEffort
        let actual: ReadinessRepository.ForecastEffort
    }

    /// What how rides feel did to the replay: the days it changed tomorrow's suggestion, whether
    /// each came out closer to the real morning, and the headline counts without it.
    struct FeelEffect: Equatable {
        let changedDays: Int
        let closer: Int
        let further: Int
        let same: Int
        let exactWithout: Int
        let withinOneWithout: Int
    }

    let daysChecked: Int
    /// With how rides feel, like the live plan.
    let exact: Int
    /// The same level or one step off, so it includes `exact`. With how rides feel.
    let withinOne: Int
    let feel: FeelEffect
    /// Newest first, at most `ForecastPlanner.maximumListedMisses`.
    let recentMisses: [Miss]
    let recoveryDays: Int
    let episodeCount: Int
}

extension ForecastPlanner {
    static let maximumListedMisses = 10

    /// For each of the last `days` days D with a score on D and D+1, learns only from the days
    /// before D, plans from D's score and actual load, and compares day 1 with the band D+1's
    /// real score fell in. Recovery bands and recovery time only: pattern and note history
    /// isn't dated, and the load ceiling is held open so the two caps' effects stay separate.
    /// An estimate: stored rows already include that day's ride, and the live plan starts from
    /// a score without it, so ride days read a little harsher here than they do live.
    /// Each day is planned twice, with and without how rides feel. The feel trend for D sees
    /// ratings up to the end of D, like the live plan (D's own rides only as comparisons, since
    /// the trend skips the current day), and never a later one.
    static func replay(history: [ForecastHistoryDay], ratedRides: [RatedRide] = [], days: Int, today: Date,
                       calendar: Calendar) -> ForecastCheckResult {
        let start = calendar.startOfDay(for: today)
        let byDay = Dictionary(history.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { $1 })
        var checked = 0, exact = 0, withinOne = 0, exactWithout = 0, withinOneWithout = 0
        var changed = 0, closer = 0, further = 0, same = 0
        var misses: [ForecastCheckResult.Miss] = []

        for back in stride(from: days, through: 2, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -back, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: date),
                  let noon = calendar.date(byAdding: .hour, value: 12, to: date),
                  let score = byDay[date]?.score, let nextScore = byDay[next]?.score
            else { continue }
            let before = history.filter { calendar.startOfDay(for: $0.date) < date }
            guard let profile = ForecastProfile.learn(history: before, today: date, calendar: calendar) else { continue }

            var input = ForecastPlanInput(now: noon, startScore: score, currentScore: score,
                                          rodeLoadToday: byDay[date]?.load ?? 0, recentLoads: before,
                                          profile: profile, firstDayIsFinished: true, projectedACWR: { _, _ in 1.0 })
            let without = plan(input, calendar: calendar)[1].effort
            let earlierRides = ratedRides.filter { $0.date < next }
            input.absorptionTrend = EffortAbsorption.trend(earlierRides, now: noon, calendar: calendar)
            let suggested = input.absorptionTrend == 0 ? without : plan(input, calendar: calendar)[1].effort
            let actual = profile.band(z: profile.z(Double(nextScore)))

            checked += 1
            let distance = abs(suggested.rawValue - actual.rawValue)
            let distanceWithout = abs(without.rawValue - actual.rawValue)
            if distanceWithout == 0 { exactWithout += 1 }
            if distanceWithout <= 1 { withinOneWithout += 1 }
            if suggested != without {
                changed += 1
                if distance < distanceWithout { closer += 1 } else if distance > distanceWithout { further += 1 } else { same += 1 }
            }
            if distance == 0 { exact += 1 }
            if distance <= 1 {
                withinOne += 1
            } else {
                misses.append(.init(date: next, suggested: suggested, actual: actual))
            }
        }

        let current = ForecastProfile.learn(history: history, today: start, calendar: calendar)
        return ForecastCheckResult(daysChecked: checked, exact: exact, withinOne: withinOne,
                                   feel: .init(changedDays: changed, closer: closer, further: further, same: same,
                                               exactWithout: exactWithout, withinOneWithout: withinOneWithout),
                                   recentMisses: Array(misses.reversed().prefix(maximumListedMisses)),
                                   recoveryDays: current?.recoveryDays ?? ForecastProfile.defaultRecoveryDays,
                                   episodeCount: current?.episodeCount ?? 0)
    }
}
