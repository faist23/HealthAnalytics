//
//  EffortAbsorptionTests.swift
//  HealthAnalyticsTests
//
//  How a rated ride felt against comparable rides, and the decaying trend that shifts the plan.
//

import XCTest
import SwiftUI
@testable import HealthAnalytics

final class EffortAbsorptionTests: XCTestCase {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func ride(_ rating: Double, daysAgo: Int = 1, minutes: Double = 60, loadPerHour: Double = 2.0) -> RatedRide {
        RatedRide(date: calendar.date(byAdding: .hour, value: 9, to: calendar.date(byAdding: .day, value: -daysAgo, to: today)!)!,
                  minutes: minutes, loadPerHour: loadPerHour, rating: rating)
    }

    // MARK: - Felt difference

    func testFeltDifference_medianOfComparableRides() throws {
        let history = [ride(5, daysAgo: 10), ride(5, daysAgo: 12), ride(6, daysAgo: 14), ride(7, daysAgo: 16)]
        let target = ride(8, daysAgo: 1)
        XCTAssertEqual(try XCTUnwrap(EffortAbsorption.feltDifference(target, among: history + [target])), 2.5, accuracy: 0.001)
    }

    func testFeltDifference_underThreeComparableIsNil() {
        let target = ride(8)
        XCTAssertNil(EffortAbsorption.feltDifference(target, among: [ride(5, daysAgo: 10), ride(5, daysAgo: 12), target]))
    }

    func testFeltDifference_excludesRidesOutsideTolerance() {
        let target = ride(8)
        let history = [ride(5, daysAgo: 10), ride(5, daysAgo: 12),
                       ride(5, daysAgo: 14, minutes: 120), ride(5, daysAgo: 16, loadPerHour: 3.0)]
        XCTAssertNil(EffortAbsorption.feltDifference(target, among: history + [target]),
                     "Only two rides are within 30% duration and 20% load per hour")
    }

    func testFeltDifference_excludesRidesOlderThan90Days() {
        let target = ride(8)
        let history = [ride(5, daysAgo: 10), ride(5, daysAgo: 12), ride(5, daysAgo: 95)]
        XCTAssertNil(EffortAbsorption.feltDifference(target, among: history + [target]))
    }

    func testFeltDifference_deadBandIsZero() {
        let history = [ride(5, daysAgo: 10), ride(5, daysAgo: 12), ride(5, daysAgo: 14)]
        XCTAssertEqual(EffortAbsorption.feltDifference(ride(6), among: history), 0)
        XCTAssertEqual(EffortAbsorption.feltDifference(ride(4), among: history), 0)
        XCTAssertEqual(EffortAbsorption.feltDifference(ride(3), among: history), -2)
    }

    func testFeltDifference_zeroLoadRideIsSkipped() {
        let history = [ride(5, daysAgo: 10), ride(5, daysAgo: 12), ride(5, daysAgo: 14)]
        XCTAssertNil(EffortAbsorption.feltDifference(ride(8, loadPerHour: 0), among: history))
        XCTAssertNil(EffortAbsorption.feltDifference(ride(8, minutes: 0.5), among: history))
        let zeroHistory = [ride(5, daysAgo: 10, loadPerHour: 0), ride(5, daysAgo: 12, loadPerHour: 0), ride(5, daysAgo: 14, loadPerHour: 0)]
        XCTAssertNil(EffortAbsorption.feltDifference(ride(8), among: zeroHistory), "Zero-load rides are never comparable")
    }

    func testFeltDifference_ignoresTheRideItself() {
        let target = ride(8)
        XCTAssertNil(EffortAbsorption.feltDifference(target, among: [ride(5, daysAgo: 10), ride(5, daysAgo: 12), target, target]))
    }

    // MARK: - Trend

    private var baseline: [RatedRide] { (20...40).map { ride(5, daysAgo: $0) } }

    func testTrend_weightsRecentRidesMore() {
        let recentHard = EffortAbsorption.trend(baseline + [ride(7, daysAgo: 1), ride(5, daysAgo: 8)], now: Date(), calendar: calendar)
        let olderHard = EffortAbsorption.trend(baseline + [ride(5, daysAgo: 1), ride(7, daysAgo: 8)], now: Date(), calendar: calendar)
        XCTAssertGreaterThan(recentHard, olderHard)
        XCTAssertGreaterThan(olderHard, 0)
    }

    /// Design: one odd rating moves the plan a little, and a run of them moves it more.
    func testTrend_oneOddRideMovesLessThanARun() {
        let one = EffortAbsorption.trend(baseline + [ride(8, daysAgo: 1)], now: Date(), calendar: calendar)
        let run = EffortAbsorption.trend(baseline + (1...4).map { ride(8, daysAgo: $0) }, now: Date(), calendar: calendar)
        XCTAssertLessThan(abs(EffortAbsorption.zShift(trend: one)), abs(EffortAbsorption.zShift(trend: run)))
        XCTAssertLessThan(abs(EffortAbsorption.zShift(trend: one)), EffortAbsorption.maximumShift)
    }

    func testTrend_anOldRideFades() {
        let old = EffortAbsorption.trend(baseline + [ride(8, daysAgo: 13)], now: Date(), calendar: calendar)
        XCTAssertLessThan(old, 0.5, "A 13-day-old ride alone barely moves the trend")
    }

    func testTrend_todaysRidesAndOlderThan14DaysDontCount() {
        let rides = baseline + [ride(8, daysAgo: 0), ride(8, daysAgo: 15)]
        XCTAssertEqual(EffortAbsorption.trend(rides, now: Date(), calendar: calendar), 0)
    }

    func testTrend_noJudgedRidesIsZero() {
        XCTAssertEqual(EffortAbsorption.trend([ride(8, daysAgo: 1)], now: Date(), calendar: calendar), 0)
        XCTAssertEqual(EffortAbsorption.trend([], now: Date(), calendar: calendar), 0)
    }

    func testTrend_easierRidesGoNegative() {
        let rides = baseline + [ride(3, daysAgo: 2)]
        let weight = pow(0.5, 2.0 / EffortAbsorption.halfLifeDays)
        XCTAssertEqual(EffortAbsorption.trend(rides, now: Date(), calendar: calendar),
                       -2 * weight / (weight + EffortAbsorption.priorWeight), accuracy: 0.001)
    }

    // MARK: - Shift

    func testZShift_signAndClamp() {
        XCTAssertEqual(EffortAbsorption.zShift(trend: 2), -1.0)
        XCTAssertEqual(EffortAbsorption.zShift(trend: -1), 0.5)
        XCTAssertEqual(EffortAbsorption.zShift(trend: 5), -1.0)
        XCTAssertEqual(EffortAbsorption.zShift(trend: -5), 1.0)
        XCTAssertEqual(EffortAbsorption.zShift(trend: 0), 0)
    }

    // MARK: - Effort Check wording

    func testTrendText_matchesTheShiftItDescribes() {
        XCTAssertEqual(EffortCheckView.trendText(0), "Rides are feeling about as usual.")
        XCTAssertEqual(EffortCheckView.trendText(0.3), "Rides are feeling about 0.3 points harder than usual.",
                       "A trend that shifts the plan is never described as usual")
        XCTAssertEqual(EffortCheckView.trendText(-1.24), "Rides are feeling about 1.2 points easier than usual.")
    }

    func testDifferenceText() {
        XCTAssertEqual(EffortCheckView.differenceText(nil), "not judged")
        XCTAssertEqual(EffortCheckView.differenceText(0), "as usual")
        XCTAssertEqual(EffortCheckView.differenceText(2.5), "+2.5")
        XCTAssertEqual(EffortCheckView.differenceText(-2), "-2.0")
    }
}
