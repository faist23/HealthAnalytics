//
//  RideCost.swift
//  HealthAnalytics
//
//  What a ride cost against what its intensity should cost Craig at his current fitness
//  (Craig: "if i have what should be a moderate intensity ride and my heart rate is much higher
//  than it should be for a moderate ride something is impacting my health"). Heart rate is the
//  main part, the Apple Watch rating adds to it; both are judged against his own rides in the
//  same setting at the same intensity. A costly ride is flagged on Coach, and the recent trend
//  eases the 7-day plan. Spec: docs/superpowers/specs/2026-11-09-ride-cost-design.md
//

import Foundation

/// A ride that can be priced: cycling with heart rate, power, a real FTP and a known setting.
struct PricedRide: Equatable {
    let id: String
    let date: Date
    let title: String?
    let minutes: Double
    /// Normalized power ÷ FTP on the ride's date.
    let intensity: Double
    let heartRate: Double
    /// Apple Watch effort rating, 1-10; nil when unrated.
    let rating: Double?
    let isIndoor: Bool
}

/// One ride against its normal. Each part is nil when it couldn't be judged.
struct RidePrice: Equatable {
    /// Beats per minute above the normal for this effort, after the dead band.
    let heartRateCost: Double?
    let normalHeartRate: Double?
    /// Rating points above the normal rating, after the dead band.
    let feelCost: Double?
    let normalRating: Double?
    /// In rating points (4 bpm = 1). Positive costs more than it should. Nil when neither part was judged.
    let cost: Double?
}

/// Why a cycling ride wasn't priced, in the order it is checked.
enum UnpricedReason: String, CaseIterable {
    case tooShort, noPower, noHeartRate, noFTP, unknownSetting

    var text: String {
        switch self {
        case .tooShort: return "Under 20 minutes"
        case .noPower: return "No measured power"
        case .noHeartRate: return "No heart rate"
        case .noFTP: return "No FTP on record for its date"
        case .unknownSetting: return "Indoor or outdoor not known yet"
        }
    }
}

enum RidePricing: Equatable {
    case priced(PricedRide)
    case unpriced(UnpricedReason)
}

/// The Coach card's ride: the newest recent ride that cost clearly more than it should.
struct RideCostFlag: Equatable {
    let date: Date
    let title: String?
    /// Set when heart rate crossed the flag line.
    let heartRateAbove: Int?
    /// Set when the feel crossed the flag line.
    let rating: Int?
    let normalRating: Int?
    /// The plan was eased by ride cost.
    var eased = false

    /// Describes the ride and never guesses a cause.
    var lines: [String] {
        var lines: [String] = []
        if let heartRateAbove { lines.append("Heart rate \(heartRateAbove) bpm above your normal for this effort") }
        if let rating, let normalRating {
            // The flag fires 2 points up, inside one word's range, so matching words show only the numbers.
            lines.append(Self.word(rating) == Self.word(normalRating)
                ? "Rated \(rating) where rides like it are rated \(normalRating)"
                : "Felt \(Self.word(rating)) (\(rating)) where rides like it feel \(Self.word(normalRating)) (\(normalRating))")
        }
        if eased { lines.append("The coming days are eased.") }
        return lines
    }

    /// Apple's effort scale.
    static func word(_ rating: Int) -> String {
        switch rating {
        case ...3: return "easy"
        case 4...6: return "moderate"
        case 7...8: return "hard"
        default: return "all out"
        }
    }
}

/// What Effort Check shows: each priced ride from the last 30 days against its normal, the rides
/// that couldn't be priced and why, and the trend the plan uses.
struct RideCostSummary: Equatable {
    struct Row: Equatable {
        let ride: PricedRide
        let price: RidePrice
    }
    /// Newest first.
    let rows: [Row]
    let unpriced: [UnpricedReason: Int]
    let trend: Double

    static let shownDays = 30
}

enum RideCost {
    static let historyDays = 90
    static let trendDays = 14
    static let minimumMinutes = 20.0
    static let minimumComparable = 3
    static let intensityTolerance = 0.05
    static let durationTolerance = 0.30
    static let heartRateDeadBand = 4.0
    static let feelDeadBand = 1.0
    static let bpmPerPoint = 4.0
    static let flagHeartRate = 8.0
    static let flagFeel = 2.0
    /// The card shows a ride from today or the two days before.
    static let flagDays = 3
    static let halfLifeDays = 4.0
    /// Weight of an imagined as-usual ride in every trend, so one odd ride moves the plan a little.
    static let priorWeight = 1.0
    static let shiftPerPoint = 0.5
    static let maximumShift = 1.0
    /// The plan's reason on a day ride cost changed the word.
    static let costlierReason = "Rides costing more than usual"
    static let cheaperReason = "Rides costing less than usual"

    /// The FTP in effect on `date` from a real snapshot. Nil when none is dated on or before it:
    /// the 200 W stand-in would make the intensity meaningless.
    static func realFTP(for date: Date, snapshots: [StoredFTPSnapshot]) -> Double? {
        snapshots.filter { $0.date <= date }.max { $0.date < $1.date }.map { Double($0.watts) }
    }

    /// Nil for anything that isn't a ride. Only normalized power counts: Strava gives it only from
    /// measured power, while its average watts for a ride with no power meter is an estimate, and
    /// mixing average-power rides with NP rides would compare unlike efforts (Craig, review D1).
    static func pricing(id: String, date: Date, title: String?, minutes: Double, isCycling: Bool,
                        normalizedPower: Double?, heartRate: Double?, rating: Double?,
                        isIndoor: Bool?, ftp: Double?) -> RidePricing? {
        guard isCycling else { return nil }
        guard minutes >= minimumMinutes else { return .unpriced(.tooShort) }
        guard let power = normalizedPower, power > 0 else { return .unpriced(.noPower) }
        guard let heartRate, heartRate > 0 else { return .unpriced(.noHeartRate) }
        guard let ftp, ftp > 0 else { return .unpriced(.noFTP) }
        guard let isIndoor else { return .unpriced(.unknownSetting) }
        return .priced(PricedRide(id: id, date: date, title: title, minutes: minutes, intensity: power / ftp,
                                  heartRate: heartRate, rating: rating, isIndoor: isIndoor))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard values.count >= minimumComparable else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Against Craig's rides in the 90 days before this one, in the same setting, at an intensity
    /// within ±0.05 and a duration within 30%.
    static func price(_ ride: PricedRide, among rides: [PricedRide]) -> RidePrice {
        let window = TimeInterval(historyDays) * 86_400
        let comparable = rides.filter { other in
            other.id != ride.id && other.isIndoor == ride.isIndoor
                && other.date < ride.date && ride.date.timeIntervalSince(other.date) <= window
                && abs(other.intensity - ride.intensity) <= intensityTolerance + 1e-9
                && abs(other.minutes - ride.minutes) <= durationTolerance * ride.minutes
        }

        let normalHeartRate = median(comparable.map(\.heartRate))
        let heartRateCost = normalHeartRate.map { normal -> Double in
            let difference = ride.heartRate - normal
            return abs(difference) <= heartRateDeadBand ? 0 : difference
        }
        let normalRating = ride.rating == nil ? nil : median(comparable.compactMap(\.rating))
        let feelCost: Double? = {
            guard let rating = ride.rating, let normalRating else { return nil }
            let difference = rating - normalRating
            return abs(difference) <= feelDeadBand ? 0 : difference
        }()

        var cost: Double?
        if heartRateCost != nil || feelCost != nil {
            var heartPoints = (heartRateCost ?? 0) / bpmPerPoint
            var feelPoints = feelCost ?? 0
            // Low heart rate with a hard feel points to overreaching, not a cheap ride, and an easy
            // feel doesn't excuse a high heart rate: a ride is cheaper only when neither part is high.
            if feelPoints > 0, heartPoints < 0 { heartPoints = 0 }
            if heartPoints > 0, feelPoints < 0 { feelPoints = 0 }
            cost = heartPoints + feelPoints
        }
        return RidePrice(heartRateCost: heartRateCost, normalHeartRate: normalHeartRate,
                         feelCost: feelCost, normalRating: normalRating, cost: cost)
    }

    private static func age(_ ride: PricedRide, now: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: ride.date), to: calendar.startOfDay(for: now)).day
    }

    /// Weighted mean ride cost over the 14 complete days before `now`, each ride's weight halving
    /// every four days, shrunk toward 0 by `priorWeight`. Today's rides wait: today's word already
    /// reflects them.
    static func trend(_ rides: [PricedRide], now: Date, calendar: Calendar) -> Double {
        var weighted = 0.0, total = 0.0
        for ride in rides {
            guard let age = age(ride, now: now, calendar: calendar), age >= 1, age <= trendDays,
                  let cost = price(ride, among: rides).cost
            else { continue }
            let weight = pow(0.5, Double(age) / halfLifeDays)
            weighted += weight * cost
            total += weight
        }
        return total > 0 ? weighted / (total + priorWeight) : 0
    }

    /// Rides costing more lower the plan's start; less lifts it. Clamped so ride cost can't
    /// outvote recovery on its own.
    static func zShift(trend: Double) -> Double {
        min(max(-shiftPerPoint * trend, -maximumShift), maximumShift)
    }

    /// The newest ride from today or the two days before whose heart rate ran 8 bpm or more over
    /// its normal, or that felt 2 points or more harder. Nil when none did.
    static func flag(_ rides: [PricedRide], now: Date, calendar: Calendar) -> RideCostFlag? {
        for ride in rides.sorted(by: { $0.date > $1.date }) {
            guard let age = age(ride, now: now, calendar: calendar), age >= 0, age < flagDays else { continue }
            let price = price(ride, among: rides)
            let heartHigh = (price.heartRateCost ?? 0) >= flagHeartRate
            let feelHigh = (price.feelCost ?? 0) >= flagFeel
            guard heartHigh || feelHigh else { continue }
            return RideCostFlag(date: ride.date, title: ride.title,
                                heartRateAbove: heartHigh ? price.heartRateCost.map { Int($0.rounded()) } : nil,
                                rating: feelHigh ? ride.rating.map { Int($0.rounded()) } : nil,
                                normalRating: feelHigh ? price.normalRating.map { Int($0.rounded()) } : nil)
        }
        return nil
    }
}
