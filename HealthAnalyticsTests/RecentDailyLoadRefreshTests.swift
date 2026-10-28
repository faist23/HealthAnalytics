//
//  RecentDailyLoadRefreshTests.swift
//  HealthAnalyticsTests
//
//  A ride that syncs after its day's row was written (an evening ride after a mid-day
//  open, a Strava upload the next morning) must reach that day's dailyLoad and
//  workoutCount. Only those two fields move: readinessScore and dailyStrain (ACWR) are
//  never rewritten, today's row stays owned by upsertDailyScore, and no row is inserted.
//

import XCTest
import HealthKit
import SwiftData
@testable import HealthAnalytics

@MainActor
final class RecentDailyLoadRefreshTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    private func ride(at start: Date, minutes: Double = 60) -> WorkoutData {
        WorkoutData(workoutType: .cycling, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
                    duration: minutes * 60, totalEnergyBurned: nil, totalDistance: nil,
                    averagePower: nil, averageHeartRate: nil, source: .appleWatch)
    }

    /// Every workout weighs its minutes, so sums are easy to read.
    private func minutes(_ w: WorkoutData) -> Double { w.duration / 60 }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredDailyScore.self, StoredWorkout.self, StoredFTPSnapshot.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // MARK: - Which days

    func test_completeDays_areTheSevenDaysEndingYesterday_neverToday() {
        let days = RecentDailyLoadRefresh.completeDays(count: RecentDailyLoadRefresh.recentLoadRecomputeDays, now: Date())
        XCTAssertEqual(days, (1...7).reversed().map { day(-$0) })
        XCTAssertFalse(days.contains(today))
    }

    func test_daysToRefresh_upgradeRunsNinetyDaysOnce_thenSeven() {
        XCTAssertEqual(RecentDailyLoadRefresh.daysToRefresh(upgradeDone: false), 90)
        XCTAssertEqual(RecentDailyLoadRefresh.daysToRefresh(upgradeDone: true), 7)
    }

    /// A 23-hour DST day: days are calendar days (startOfDay arithmetic), not 24h steps.
    func test_completeDays_acrossADSTChange_areCalendarDays() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-03-08 is the US spring-forward day; "now" is noon two days later.
        let now = ny.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let days = RecentDailyLoadRefresh.completeDays(count: 3, now: now, calendar: ny)

        let expected = [7, 8, 9].map { ny.date(from: DateComponents(year: 2026, month: 3, day: $0))! }
        XCTAssertEqual(days, expected)
    }

    // MARK: - Loads

    /// The late ride lands at 23:59 on its own day, not on the next one.
    func test_loads_lateRideCountsOnItsOwnDay() {
        let days = RecentDailyLoadRefresh.completeDays(count: 7, now: Date())
        let lateOnDayMinus3 = day(-2).addingTimeInterval(-60)
        let result = RecentDailyLoadRefresh.loads(
            days: days,
            workouts: [ride(at: day(-3).addingTimeInterval(8 * 3600), minutes: 30), ride(at: lateOnDayMinus3, minutes: 45)],
            load: minutes
        )
        XCTAssertEqual(result[day(-3)], .init(dailyLoad: 75, workoutCount: 2))
        XCTAssertEqual(result[day(-2)], .init(dailyLoad: 0, workoutCount: 0))
    }

    func test_loads_everyDayGetsAnEntry_andWorkoutsOutsideTheDaysAreIgnored() {
        let days = RecentDailyLoadRefresh.completeDays(count: 7, now: Date())
        let result = RecentDailyLoadRefresh.loads(
            days: days,
            workouts: [ride(at: today.addingTimeInterval(3600)), ride(at: day(-8).addingTimeInterval(3600))],
            load: minutes
        )
        XCTAssertEqual(Set(result.keys), Set(days))
        XCTAssertTrue(result.values.allSatisfy { $0 == .init(dailyLoad: 0, workoutCount: 0) })
    }

    func test_loads_acrossADSTChange_lateRideStaysOnTheShortDay() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let now = ny.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let days = RecentDailyLoadRefresh.completeDays(count: 3, now: now, calendar: ny)
        let dstDay = days[1]                      // 2026-03-08, 23 hours long
        let lateOnDSTDay = days[2].addingTimeInterval(-60)

        let result = RecentDailyLoadRefresh.loads(days: days, workouts: [ride(at: lateOnDSTDay)], calendar: ny, load: minutes)

        XCTAssertEqual(result[dstDay], .init(dailyLoad: 60, workoutCount: 1))
        XCTAssertEqual(result[days[2]], .init(dailyLoad: 0, workoutCount: 0))
    }

    // MARK: - Applying to rows

    func test_apply_updatesLoadAndCountOnEveryTwin_neverScoreOrStrain() throws {
        let ctx = ModelContext(try makeContainer())
        let a = StoredDailyScore(date: day(-3), readinessScore: 71, dailyStrain: 1.12, workoutCount: 1, dailyLoad: 30)
        let b = StoredDailyScore(date: day(-3), readinessScore: 64, dailyStrain: 0.97, workoutCount: 1, dailyLoad: 30)
        ctx.insert(a); ctx.insert(b)

        let changed = RecentDailyLoadRefresh.apply([day(-3): .init(dailyLoad: 75, workoutCount: 2)], to: [a, b])

        XCTAssertEqual(changed, 2)
        for row in [a, b] {
            XCTAssertEqual(row.dailyLoad, 75)
            XCTAssertEqual(row.workoutCount, 2)
        }
        XCTAssertEqual(a.readinessScore, 71); XCTAssertEqual(a.dailyStrain, 1.12)
        XCTAssertEqual(b.readinessScore, 64); XCTAssertEqual(b.dailyStrain, 0.97)
    }

    func test_apply_unchangedData_reportsNoChange() throws {
        let ctx = ModelContext(try makeContainer())
        let row = StoredDailyScore(date: day(-2), readinessScore: 70, dailyStrain: 1.0, workoutCount: 2, dailyLoad: 75)
        ctx.insert(row)

        XCTAssertEqual(RecentDailyLoadRefresh.apply([day(-2): .init(dailyLoad: 75, workoutCount: 2)], to: [row]), 0)
    }

    /// Today's row (upsertDailyScore owns it) and rows outside the window are untouched,
    /// even when they are handed in.
    func test_apply_daysWithoutALoadEntry_areUntouched() throws {
        let ctx = ModelContext(try makeContainer())
        let todayRow = StoredDailyScore(date: today, readinessScore: 70, dailyStrain: 1.0, workoutCount: 0, dailyLoad: 0)
        let oldRow = StoredDailyScore(date: day(-10), readinessScore: 70, dailyStrain: 1.0, workoutCount: 0, dailyLoad: 0)
        ctx.insert(todayRow); ctx.insert(oldRow)
        let days = RecentDailyLoadRefresh.completeDays(count: 7, now: Date())
        let loads = Dictionary(uniqueKeysWithValues: days.map { ($0, RecentDailyLoadRefresh.DayLoad(dailyLoad: 50, workoutCount: 1)) })

        XCTAssertEqual(RecentDailyLoadRefresh.apply(loads, to: [todayRow, oldRow]), 0)
        XCTAssertEqual(todayRow.dailyLoad, 0)
        XCTAssertEqual(oldRow.dailyLoad, 0)
    }

    // MARK: - Repository wiring (in-memory store, no HealthKit)

    func test_refreshDailyLoads_lateRideReachesItsDay_onlyLoadAndCountMove_noRowInserted() throws {
        let key = "lastPatternAnalysisDate"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let ctx = ModelContext(try makeContainer())
        let stale = StoredDailyScore(date: day(-3), readinessScore: 71, dailyStrain: 1.12, workoutCount: 0, dailyLoad: 0)
        let todayRow = StoredDailyScore(date: today, readinessScore: 80, dailyStrain: 1.0, workoutCount: 0, dailyLoad: 0)
        let oldRow = StoredDailyScore(date: day(-10), readinessScore: 60, dailyStrain: 1.0, workoutCount: 0, dailyLoad: 0)
        [stale, todayRow, oldRow].forEach(ctx.insert)
        for (id, start) in [("late", day(-2).addingTimeInterval(-60)), ("today", today.addingTimeInterval(3600)), ("old", day(-10).addingTimeInterval(3600))] {
            ctx.insert(StoredWorkout(id: id, type: .cycling, startDate: start, duration: 3600,
                                     distance: nil, power: nil, energy: nil, hr: nil, source: "Apple Watch"))
        }
        try ctx.save()
        UserDefaults.standard.set(Date(), forKey: key)

        let changed = ReadinessRepository.shared.refreshDailyLoads(modelContext: ctx, days: 7)

        XCTAssertEqual(changed, 1)
        XCTAssertGreaterThan(stale.dailyLoad, 0)
        XCTAssertEqual(stale.workoutCount, 1)
        XCTAssertEqual(stale.readinessScore, 71)
        XCTAssertEqual(stale.dailyStrain, 1.12)
        XCTAssertEqual(todayRow.dailyLoad, 0, "Today's row belongs to upsertDailyScore")
        XCTAssertEqual(oldRow.dailyLoad, 0, "Outside the window")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<StoredDailyScore>()), 3, "Missing days stay the backfill's job")
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "A late ride changes what detectors see")

        // A second run finds nothing to change and leaves the pattern stamp alone.
        let stamp = Date()
        UserDefaults.standard.set(stamp, forKey: key)
        XCTAssertEqual(ReadinessRepository.shared.refreshDailyLoads(modelContext: ctx, days: 7), 0)
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Date, stamp)
    }
}
