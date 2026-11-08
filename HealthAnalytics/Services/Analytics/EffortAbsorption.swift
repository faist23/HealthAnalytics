//
//  EffortAbsorption.swift
//  HealthAnalytics
//
//  How rides feel, read as how well the body is absorbing work (Craig: "the self rating should
//  help with how my body is adapting at that time. HRV may indicate similar idea"). Each rated
//  ride is compared with Craig's ratings of comparable rides; the recent differences form a
//  decaying trend that shifts the 7-day plan beside HRV. Spec:
//  docs/superpowers/specs/2026-11-07-effort-drift-design.md
//

import Foundation

/// A ride with an Apple-written effort rating and the work it represents.
struct RatedRide: Equatable {
    let date: Date
    let minutes: Double
    /// `calculateWorkoutLoad` per hour of riding.
    let loadPerHour: Double
    /// 1-10, from Apple Watch.
    let rating: Double
}

/// What Effort Check shows about how rides have felt: each recent rated ride against its usual,
/// and the trend the plan uses.
struct AbsorptionSummary: Equatable {
    struct Ride: Equatable {
        let date: Date
        let rating: Double
        /// Median rating of comparable rides; nil under three.
        let expected: Double?
        /// Felt difference after the dead band; nil when not judged.
        let difference: Double?
    }
    /// Newest first, last 30 days.
    let rides: [Ride]
    let trend: Double

    static let shownDays = 30
}

enum EffortAbsorption {
    static let historyDays = 90
    static let trendDays = 14
    static let minimumComparable = 3
    /// Comparable rides are within these fractions of the ride's duration and load per hour.
    static let durationTolerance = 0.30
    static let intensityTolerance = 0.20
    /// A difference this size or smaller is rating noise and counts as zero.
    static let deadBand = 1.0
    static let halfLifeDays = 4.0
    /// Weight of an imagined "felt as usual" ride added to every trend, so one odd rating moves the
    /// plan a little, a run of them more, and an old lone rating fades instead of standing at full size.
    static let priorWeight = 1.0
    /// Plan shift in spreads per rating point of trend, and its limit either way.
    static let shiftPerPoint = 0.5
    static let maximumShift = 1.0

    /// A ride that carries a usable amount of work to compare.
    private static func isJudgeable(_ ride: RatedRide) -> Bool {
        ride.loadPerHour > 0 && ride.minutes >= 1
    }

    /// Median rating of comparable rides within 90 days either side; nil under three or for a
    /// ride with no usable work.
    static func expectedRating(_ ride: RatedRide, among rides: [RatedRide]) -> Double? {
        guard isJudgeable(ride) else { return nil }
        let window = TimeInterval(historyDays) * 86_400
        let comparable = rides.filter { other in
            other != ride && isJudgeable(other)
                && abs(other.date.timeIntervalSince(ride.date)) <= window
                && abs(other.minutes - ride.minutes) <= durationTolerance * ride.minutes
                && abs(other.loadPerHour - ride.loadPerHour) <= intensityTolerance * ride.loadPerHour
        }.map(\.rating).sorted()
        guard comparable.count >= minimumComparable else { return nil }
        let mid = comparable.count / 2
        return comparable.count % 2 == 0 ? (comparable[mid - 1] + comparable[mid]) / 2 : comparable[mid]
    }

    /// Rating minus the median rating of comparable rides within 90 days either side; nil under
    /// three comparable rides or for a ride with no usable work. Within the dead band reads 0.
    static func feltDifference(_ ride: RatedRide, among rides: [RatedRide]) -> Double? {
        guard let median = expectedRating(ride, among: rides) else { return nil }
        let difference = ride.rating - median
        return abs(difference) <= deadBand ? 0 : difference
    }

    /// Weighted mean felt difference over the 14 complete days before `now`, each ride's weight
    /// halving every four days, shrunk toward 0 by `priorWeight`. 0 when no ride can be judged. Today's rides wait:
    /// today's word already reflects them.
    static func trend(_ rides: [RatedRide], now: Date, calendar: Calendar) -> Double {
        let today = calendar.startOfDay(for: now)
        var weighted = 0.0, total = 0.0
        for ride in rides {
            guard let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: ride.date), to: today).day,
                  age >= 1, age <= trendDays,
                  let difference = feltDifference(ride, among: rides)
            else { continue }
            let weight = pow(0.5, Double(age) / halfLifeDays)
            weighted += weight * difference
            total += weight
        }
        return total > 0 ? weighted / (total + priorWeight) : 0
    }

    /// Rides feeling harder lowers the plan's start; easier lifts it. Clamped so feel can't
    /// outvote recovery on its own.
    static func zShift(trend: Double) -> Double {
        min(max(-shiftPerPoint * trend, -maximumShift), maximumShift)
    }
}
