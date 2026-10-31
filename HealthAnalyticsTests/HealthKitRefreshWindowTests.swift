//
//  HealthKitRefreshWindowTests.swift
//  HealthAnalyticsTests
//
//  Where the background pass's HealthKit-only workout refresh starts reading: the later
//  of the last background refresh and the last full sync (else a week back), minus one
//  day of overlap so a ride that HealthKit reported late is still picked up.
//

import XCTest
@testable import HealthAnalytics

final class HealthKitRefreshWindowTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func oneDayBefore(_ date: Date) -> Date { cal.date(byAdding: .day, value: -1, to: date)! }

    func test_neverRefreshedNorSynced_readsAWeekBackPlusOneDay() {
        let start = SyncManager.healthKitRefreshWindowStart(lastBackgroundRefresh: nil, lastSync: nil, now: now)
        XCTAssertEqual(start, oneDayBefore(now.addingTimeInterval(-7 * 86400)))
    }

    func test_lastSyncNewer_startsOneDayBeforeTheSync() {
        let refresh = now.addingTimeInterval(-10 * 3600)
        let sync = now.addingTimeInterval(-2 * 3600)
        let start = SyncManager.healthKitRefreshWindowStart(lastBackgroundRefresh: refresh, lastSync: sync, now: now)
        XCTAssertEqual(start, oneDayBefore(sync))
    }

    func test_lastBackgroundRefreshNewer_startsOneDayBeforeTheRefresh() {
        let refresh = now.addingTimeInterval(-1 * 3600)
        let sync = now.addingTimeInterval(-30 * 3600)
        let start = SyncManager.healthKitRefreshWindowStart(lastBackgroundRefresh: refresh, lastSync: sync, now: now)
        XCTAssertEqual(start, oneDayBefore(refresh))
    }

    /// Only one of the two is known: it is used, still with the day of overlap.
    func test_onlyOneKnown_usesIt_withTheOneDayOverlap() {
        let sync = now.addingTimeInterval(-5 * 3600)
        XCTAssertEqual(SyncManager.healthKitRefreshWindowStart(lastBackgroundRefresh: nil, lastSync: sync, now: now), oneDayBefore(sync))
        XCTAssertEqual(SyncManager.healthKitRefreshWindowStart(lastBackgroundRefresh: sync, lastSync: nil, now: now), oneDayBefore(sync))
    }
}
