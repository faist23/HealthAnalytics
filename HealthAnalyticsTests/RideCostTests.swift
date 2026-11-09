//
//  RideCostTests.swift
//  HealthAnalyticsTests
//
//  A ride priced against what its intensity should cost Craig: heart rate and feel against his
//  own same-setting rides at that intensity. Spec: docs/superpowers/specs/2026-11-09-ride-cost-design.md
//

import XCTest
@testable import HealthAnalytics

final class RideCostTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// Noon, so day ages are unambiguous.
    private let now = Date(timeIntervalSince1970: 1_793_620_800 + 12 * 3600)

    private func ride(daysAgo: Double, hr: Double = 140, intensity: Double = 0.70, minutes: Double = 60,
                      rating: Double? = nil, indoor: Bool = true, id: String? = nil) -> PricedRide {
        PricedRide(id: id ?? UUID().uuidString, date: now.addingTimeInterval(-daysAgo * 86_400), title: "Ride",
                   minutes: minutes, intensity: intensity, heartRate: hr, rating: rating, isIndoor: indoor)
    }

    /// Three usual rides 20–22 days back: HR 140, rated 5.
    private func usual(indoor: Bool = true, rating: Double? = 5, daysAgo: Double = 20) -> [PricedRide] {
        (0..<3).map { ride(daysAgo: daysAgo + Double($0), rating: rating, indoor: indoor) }
    }

    // MARK: - Price

    func testPrice_heartRate10AboveFlagsAndCosts2_5() {
        let costly = ride(daysAgo: 1, hr: 150)
        let price = RideCost.price(costly, among: usual() + [costly])
        XCTAssertEqual(price.heartRateCost, 10)
        XCTAssertEqual(price.normalHeartRate, 140)
        XCTAssertNil(price.feelCost, "An unrated ride has no feel part")
        XCTAssertEqual(price.cost, 2.5)
    }

    func testPrice_atMedianIsZero() {
        let same = ride(daysAgo: 1, hr: 140)
        XCTAssertEqual(RideCost.price(same, among: usual() + [same]).cost, 0)
    }

    func testPrice_withinDeadBandIsZero() {
        let near = ride(daysAgo: 1, hr: 144)
        XCTAssertEqual(RideCost.price(near, among: usual() + [near]).heartRateCost, 0)
        let past = ride(daysAgo: 1, hr: 145)
        XCTAssertEqual(RideCost.price(past, among: usual() + [past]).heartRateCost, 5)
    }

    func testPrice_lowHeartRateDoesNotCancelHardFeel() {
        let r = ride(daysAgo: 1, hr: 132, rating: 7)
        let price = RideCost.price(r, among: usual() + [r])
        XCTAssertEqual(price.heartRateCost, -8)
        XCTAssertEqual(price.feelCost, 2)
        XCTAssertEqual(price.cost, 2, "The feel alone")
    }

    func testPrice_highHeartRateDropsEasyFeel() {
        let r = ride(daysAgo: 1, hr: 148, rating: 2)
        let price = RideCost.price(r, among: usual() + [r])
        XCTAssertEqual(price.feelCost, -3)
        XCTAssertEqual(price.cost, 2, "Heart rate alone")
    }

    func testPrice_cheaperOnlyWhenNeitherPositive() {
        let r = ride(daysAgo: 1, hr: 132, rating: 3)
        XCTAssertEqual(RideCost.price(r, among: usual() + [r]).cost, -4)
    }

    func testPrice_feelAndHeartRateTogetherCostMoreThanEither() {
        let both = ride(daysAgo: 1, hr: 150, rating: 8)
        let price = RideCost.price(both, among: usual() + [both])
        XCTAssertEqual(price.cost, 5.5)
    }

    func testPrice_indoorNeverComparesWithOutdoor() {
        let indoor = ride(daysAgo: 1, hr: 150, indoor: true)
        let price = RideCost.price(indoor, among: usual(indoor: false) + [indoor])
        XCTAssertNil(price.heartRateCost)
        XCTAssertNil(price.cost)
    }

    /// Review focus 5.
    func testPrice_ignoresLaterRides() {
        let r = ride(daysAgo: 30, hr: 150)
        XCTAssertNil(RideCost.price(r, among: usual(daysAgo: 2) + [r]).cost, "Only rides before it are its normal")
    }

    func testPrice_olderThan90DaysNotComparable() {
        let r = ride(daysAgo: 1, hr: 150)
        XCTAssertNil(RideCost.price(r, among: usual(daysAgo: 92) + [r]).cost)
    }

    func testPrice_fewerThanThreeNotJudged() {
        let r = ride(daysAgo: 1, hr: 150)
        XCTAssertNil(RideCost.price(r, among: Array(usual().prefix(2)) + [r]).cost)
    }

    func testPrice_intensityAndDurationTolerance() {
        let r = ride(daysAgo: 1, hr: 150)
        let harder = (0..<3).map { ride(daysAgo: 20 + Double($0), intensity: 0.76) }
        XCTAssertNil(RideCost.price(r, among: harder + [r]).cost, "0.06 apart is a different intensity")
        let close = (0..<3).map { ride(daysAgo: 20 + Double($0), intensity: 0.74) }
        XCTAssertEqual(RideCost.price(r, among: close + [r]).cost, 2.5)
        let longer = (0..<3).map { ride(daysAgo: 20 + Double($0), minutes: 80) }
        XCTAssertNil(RideCost.price(r, among: longer + [r]).cost, "80 min is more than 30% longer than 60")
    }

    func testPrice_feelNeedsThreeRatedComparables() {
        let r = ride(daysAgo: 1, hr: 140, rating: 8)
        let price = RideCost.price(r, among: usual(rating: nil) + [r])
        XCTAssertNil(price.feelCost)
        XCTAssertEqual(price.cost, 0, "Still judged on heart rate")
    }

    // MARK: - Pricing a stored ride

    private func pricing(minutes: Double = 60, isCycling: Bool = true, np: Double? = 210,
                         hr: Double? = 140, isIndoor: Bool? = true, ftp: Double? = 300) -> RidePricing? {
        RideCost.pricing(id: "r", date: now, title: "Ride", minutes: minutes, isCycling: isCycling,
                         normalizedPower: np, heartRate: hr, rating: 5, isIndoor: isIndoor, ftp: ftp)
    }

    func testPricing_reasons() {
        XCTAssertNil(pricing(isCycling: false))
        XCTAssertEqual(pricing(minutes: 19), .unpriced(.tooShort))
        XCTAssertEqual(pricing(np: nil), .unpriced(.noPower))
        XCTAssertEqual(pricing(np: 0), .unpriced(.noPower))
        XCTAssertEqual(pricing(hr: nil), .unpriced(.noHeartRate))
        XCTAssertEqual(pricing(ftp: nil), .unpriced(.noFTP))
        XCTAssertEqual(pricing(isIndoor: nil), .unpriced(.unknownSetting))
        guard case .priced(let ride)? = pricing() else { return XCTFail("Should price") }
        XCTAssertEqual(ride.intensity, 0.7, accuracy: 1e-9)
    }

    /// Strava gives NP only from measured power; a ride with only its estimated average watts
    /// (no power meter) is never priced (Craig, review D1).
    func testPricing_estimatedPowerAloneIsNoPower() {
        let estimated = RideCost.pricing(id: "r", date: now, title: nil, minutes: 60, isCycling: true,
                                         normalizedPower: nil, heartRate: 140, rating: nil, isIndoor: true, ftp: 300)
        XCTAssertEqual(estimated, .unpriced(.noPower))
    }

    func testPricing_higherFTPLowersIntensity() {
        guard case .priced(let low)? = pricing(ftp: 300), case .priced(let high)? = pricing(ftp: 250)
        else { return XCTFail("Should price") }
        XCTAssertLessThan(low.intensity, high.intensity)
    }

    /// Review focus 2.
    func testPricing_snapshotAfterRideIsNoFTP() {
        let later = StoredFTPSnapshot(date: now.addingTimeInterval(86_400), watts: 280, source: "manual")
        XCTAssertNil(RideCost.realFTP(for: now, snapshots: [later]), "Never the 200 W stand-in, never a later FTP")
        let earlier = StoredFTPSnapshot(date: now.addingTimeInterval(-86_400 * 10), watts: 260, source: "manual")
        XCTAssertEqual(RideCost.realFTP(for: now, snapshots: [later, earlier]), 260)
    }

    // MARK: - Trend

    private func costly(daysAgo: Double) -> PricedRide { ride(daysAgo: daysAgo, hr: 150) }

    func testTrend_oneCostlyRideMovesLessThanSeveral() {
        let one = RideCost.trend(usual() + [costly(daysAgo: 1)], now: now, calendar: calendar)
        let several = RideCost.trend(usual() + [costly(daysAgo: 1), costly(daysAgo: 2), costly(daysAgo: 3)],
                                     now: now, calendar: calendar)
        XCTAssertGreaterThan(one, 0)
        XCTAssertLessThan(one, several)
        XCTAssertLessThan(several, 2.5, "Shrunk toward as-usual")
    }

    /// Review focus 3.
    func testTrend_skipsToday() {
        XCTAssertEqual(RideCost.trend(usual() + [costly(daysAgo: 0)], now: now, calendar: calendar), 0)
    }

    func testTrend_fades() {
        let recent = RideCost.trend(usual() + [costly(daysAgo: 1)], now: now, calendar: calendar)
        let older = RideCost.trend(usual() + [costly(daysAgo: 10)], now: now, calendar: calendar)
        XCTAssertLessThan(older, recent)
        XCTAssertEqual(RideCost.trend(usual() + [costly(daysAgo: 15)], now: now, calendar: calendar), 0)
    }

    func testZShift_clamped() {
        XCTAssertEqual(RideCost.zShift(trend: 1), -0.5)
        XCTAssertEqual(RideCost.zShift(trend: 3), -1)
        XCTAssertEqual(RideCost.zShift(trend: -3), 1)
    }

    // MARK: - Flag

    func testFlag_todaysRideFlags() {
        let flag = RideCost.flag(usual() + [costly(daysAgo: 0)], now: now, calendar: calendar)
        XCTAssertEqual(flag?.heartRateAbove, 10)
        XCTAssertNil(flag?.rating)
    }

    func testFlag_feelAlone() {
        let hard = ride(daysAgo: 1, hr: 140, rating: 8)
        let flag = RideCost.flag(usual() + [hard], now: now, calendar: calendar)
        XCTAssertNil(flag?.heartRateAbove)
        XCTAssertEqual(flag?.rating, 8)
        XCTAssertEqual(flag?.normalRating, 5)
    }

    func testFlag_belowTheLineNone() {
        XCTAssertNil(RideCost.flag(usual() + [ride(daysAgo: 1, hr: 147)], now: now, calendar: calendar),
                     "7 bpm moves the plan but isn't flagged")
    }

    func testFlag_olderThan3DaysNone() {
        XCTAssertNil(RideCost.flag(usual() + [costly(daysAgo: 3)], now: now, calendar: calendar))
    }

    func testFlag_cheaperRideNotFlagged() {
        XCTAssertNil(RideCost.flag(usual() + [ride(daysAgo: 1, hr: 128, rating: 2)], now: now, calendar: calendar))
    }

    func testFlag_newestFlaggedRideWins() {
        let older = ride(daysAgo: 2, hr: 155, id: "older")
        let newer = ride(daysAgo: 1, hr: 150, id: "newer")
        XCTAssertEqual(RideCost.flag(usual() + [older, newer], now: now, calendar: calendar)?.heartRateAbove, 10)
    }

    func testFlagLines_copy() {
        let flag = RideCostFlag(date: now, title: "Lunch Ride", heartRateAbove: 11, rating: 8, normalRating: 5, eased: true)
        XCTAssertEqual(flag.lines, ["Heart rate 11 bpm above your normal for this effort",
                                    "Felt hard (8) where rides like it feel moderate (5)",
                                    "The coming days are eased."])
        let hrOnly = RideCostFlag(date: now, title: nil, heartRateAbove: 9, rating: nil, normalRating: nil)
        XCTAssertEqual(hrOnly.lines, ["Heart rate 9 bpm above your normal for this effort"])
        let allOut = RideCostFlag(date: now, title: nil, heartRateAbove: nil, rating: 9, normalRating: 3)
        XCTAssertEqual(allOut.lines, ["Felt all out (9) where rides like it feel easy (3)"])
    }

    // MARK: - Effort Check text

    func testEffortCheckRowText() {
        let r = ride(daysAgo: 1, hr: 152, rating: 8)
        let row = RideCostSummary.Row(ride: r, price: RideCost.price(r, among: usual() + [r]))
        XCTAssertEqual(EffortCheckView.rowText(row), "indoor · IF 0.70 · HR 152 (usual 140, +12) · rated 8 (usual 5)")
        let alone = ride(daysAgo: 1, hr: 138, indoor: false)
        XCTAssertEqual(EffortCheckView.rowText(.init(ride: alone, price: RideCost.price(alone, among: [alone]))),
                       "outdoor · IF 0.70 · HR 138 (not judged)")
    }

    func testEffortCheckTrendText() {
        XCTAssertEqual(EffortCheckView.trendText(0.01), "Rides are costing about what they usually do.")
        XCTAssertEqual(EffortCheckView.trendText(1.24), "Rides are costing about 1.2 points more than usual.")
        XCTAssertEqual(EffortCheckView.trendText(-0.5), "Rides are costing about 0.5 points less than usual.")
    }

    // MARK: - Coach card

    func testCardSubtitle_namesTheDayAndRide() {
        let today = RideCostFlag(date: now, title: "Lunch Ride", heartRateAbove: 9, rating: nil, normalRating: nil)
        XCTAssertEqual(RideCostCard.subtitle(today, now: now, calendar: calendar), "Today · Lunch Ride")
        let yesterday = RideCostFlag(date: now.addingTimeInterval(-86_400), title: nil, heartRateAbove: 9,
                                     rating: nil, normalRating: nil)
        XCTAssertEqual(RideCostCard.subtitle(yesterday, now: now, calendar: calendar), "Yesterday · Ride")
        let earlier = RideCostFlag(date: now.addingTimeInterval(-2 * 86_400), title: "Zwift - Watopia", heartRateAbove: 9,
                                   rating: nil, normalRating: nil)
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: earlier.date) - 1]
        XCTAssertEqual(RideCostCard.subtitle(earlier, now: now, calendar: calendar), "\(weekday) · Zwift - Watopia")
    }
}
