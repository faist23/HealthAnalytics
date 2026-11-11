//
//  HardDayRulesTests.swift
//  HealthAnalyticsTests
//

import XCTest
@testable import HealthAnalytics

final class HardDayRulesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HardDayRulesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testForAge_bands() {
        XCTAssertEqual(HardDayRules.forAge(59), .under60)
        XCTAssertEqual(HardDayRules.forAge(60), .from60)
        XCTAssertEqual(HardDayRules.forAge(65), .from60)
        XCTAssertEqual(HardDayRules.forAge(nil), .under60)
        XCTAssertEqual(HardDayRules.from60, HardDayRules(hardDaysPerWeek: 2, minimumRecoveryDays: 2))
        XCTAssertEqual(HardDayRules.under60, HardDayRules(hardDaysPerWeek: 3, minimumRecoveryDays: 1))
    }

    func testResolvedAge_remembersTheLastGoodRead() {
        XCTAssertEqual(HardDayRules.resolvedAge(read: 65, defaults: defaults), 65)
        XCTAssertEqual(HardDayRules.resolvedAge(read: nil, defaults: defaults), 65)
        XCTAssertEqual(HardDayRules.resolvedAge(read: 66, defaults: defaults), 66)
        XCTAssertEqual(defaults.integer(forKey: HardDayRules.lastKnownAgeKey), 66)
    }

    func testResolvedAge_neverReadIsNil() {
        XCTAssertNil(HardDayRules.resolvedAge(read: nil, defaults: defaults))
    }

    func testResolvedAge_implausibleReadIsUnknownAndNotStored() {
        XCTAssertEqual(HardDayRules.resolvedAge(read: 65, defaults: defaults), 65)
        for bad in [-1, 0, 9, 111, 126] {
            XCTAssertEqual(HardDayRules.resolvedAge(read: bad, defaults: defaults), 65)
        }
        XCTAssertEqual(defaults.integer(forKey: HardDayRules.lastKnownAgeKey), 65)
    }

    func testResolvedAge_implausibleFirstReadIsNil() {
        XCTAssertNil(HardDayRules.resolvedAge(read: 0, defaults: defaults))
    }

    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// A rider remembered at 59 whose reads then stop must reach the 60+ rules a year on.
    func testResolvedAge_fallbackAddsWholeYearsSinceTheRead() {
        XCTAssertEqual(HardDayRules.resolvedAge(read: 59, defaults: defaults, now: date(2026, 3, 1), calendar: calendar), 59)
        XCTAssertEqual(HardDayRules.resolvedAge(read: nil, defaults: defaults, now: date(2026, 11, 1), calendar: calendar), 59)
        XCTAssertEqual(HardDayRules.resolvedAge(read: nil, defaults: defaults, now: date(2027, 3, 1), calendar: calendar), 60)
        XCTAssertEqual(HardDayRules.forAge(HardDayRules.resolvedAge(read: nil, defaults: defaults,
                                                                     now: date(2027, 3, 2), calendar: calendar)), .from60)
    }

    /// A read the stored age already predicts keeps the earlier read date, which only ever
    /// under-counts the years since, so a later fallback never over-states the age.
    func testResolvedAge_matchingReadIsNotRewritten() {
        _ = HardDayRules.resolvedAge(read: 65, defaults: defaults, now: date(2026, 1, 10), calendar: calendar)
        let stamp = defaults.object(forKey: HardDayRules.lastKnownAgeDateKey) as? Double
        XCTAssertNotNil(stamp)
        XCTAssertEqual(HardDayRules.resolvedAge(read: 65, defaults: defaults, now: date(2026, 6, 10), calendar: calendar), 65)
        XCTAssertEqual(defaults.object(forKey: HardDayRules.lastKnownAgeDateKey) as? Double, stamp)
        XCTAssertEqual(HardDayRules.resolvedAge(read: nil, defaults: defaults, now: date(2027, 1, 11), calendar: calendar), 66)
    }

    /// An age remembered before the read date was stored has no date to count from: it is used as is.
    func testResolvedAge_storedAgeWithoutADateIsUsedAsIs() {
        defaults.set(64, forKey: HardDayRules.lastKnownAgeKey)
        XCTAssertEqual(HardDayRules.resolvedAge(read: nil, defaults: defaults, now: date(2030, 1, 1), calendar: calendar), 64)
    }
}
