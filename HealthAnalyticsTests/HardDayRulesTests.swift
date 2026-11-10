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
}
