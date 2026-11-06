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

        return ForecastProfile(normal: normal, spread: spread, hardLoad: hardLoad, moderateLoad: moderateLoad,
                               easyLoad: easyLoad, dip: dip, recoveryDays: recoveryDays, episodeCount: found.count)
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

    private static func median(_ values: [Double]) -> Double? {
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
