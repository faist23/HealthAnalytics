//
//  ForecastPlanStoreTests.swift
//  HealthAnalyticsTests
//
//  The forecast plan read through a real (in-memory) store: what counts as history, what a
//  stored ride does to the week, and when a cached plan has to give way.
//

import XCTest
import SwiftData
import HealthKit
@testable import HealthAnalytics

@MainActor
final class ForecastPlanStoreTests: XCTestCase {

    private let calendar = Calendar.current
    private let repo = ReadinessRepository.shared
    private var ctx: ModelContext!
    private var container: ModelContainer!

    private var today: Date { calendar.startOfDay(for: Date()) }
    private var noon: Date { calendar.date(byAdding: .hour, value: 12, to: today)! }

    override func setUp() async throws {
        repo.resetForTesting()
        let schema = Schema([StoredDailyScore.self, StoredWorkout.self, StoredFTPSnapshot.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        ctx = ModelContext(container)
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func insertRows(_ range: ClosedRange<Int>, score: Int = 75, load: Double = 0) {
        for offset in range {
            ctx.insert(StoredDailyScore(date: day(-offset), readinessScore: score, dailyStrain: 1.0, workoutCount: 0, dailyLoad: load))
        }
    }

    @discardableResult
    private func insertRide(_ id: String, daysAgo: Int, hours: Double) -> StoredWorkout {
        let ride = StoredWorkout(id: id, type: .cycling, startDate: day(-daysAgo).addingTimeInterval(8 * 3600),
                                 duration: hours * 3600, distance: nil, power: nil, energy: nil, hr: nil, source: "test")
        ctx.insert(ride)
        return ride
    }

    /// 21 days of 1h then a week of 3h ending yesterday.
    private func insertRamp() {
        for offset in 8...28 { insertRide("base-\(offset)", daysAgo: offset, hours: 1) }
        for offset in 1...7 { insertRide("acute-\(offset)", daysAgo: offset, hours: 3) }
    }

    private func plan(start: Int, current: Int? = nil, patterns: Set<PatternType> = [],
                      memories: [CoachMemoryNote] = [], risk: InjuryRiskCalculator.RiskLevel = .low,
                      illness: ForecastIllness = .none) throws -> [ReadinessRepository.ReadinessForecastDay]? {
        try repo.computeForecastPlan(modelContext: ctx, startScore: start, currentScore: current ?? start,
                                     illness: illness, activePatterns: patterns, memories: memories,
                                     injuryRisk: risk, sleep: [], now: noon)?.days
    }

    // MARK: - The ACWR engine with planned loads

    func testACWR_plannedLoadsCountInsideTheWindowOnly() {
        let service = PredictiveReadinessService()
        let rides = (1...20).map { offset in
            WorkoutData(from: StoredWorkout(id: "r\(offset)", type: .cycling, startDate: day(-offset),
                                            duration: 3600, distance: nil, power: nil, energy: nil, hr: nil, source: "test"))
        }
        func acwr(_ planned: [Date: Double]) -> Double {
            service.calculateReadiness(stravaActivities: [], healthKitWorkouts: rides, referenceDate: day(1),
                                       plannedDailyLoads: planned).acwr
        }
        let base = service.calculateReadiness(stravaActivities: [], healthKitWorkouts: rides, referenceDate: day(1)).acwr
        XCTAssertEqual(acwr([:]), base, "No planned load changes nothing")
        XCTAssertGreaterThan(acwr([day(0): 5]), base)
        XCTAssertEqual(acwr([day(2): 5]), base, "A load after the window closes doesn't count")
        XCTAssertEqual(acwr([day(-40): 5]), base, "A load before the window opens doesn't count")
    }

    func testACWR_plannedLoadAloneCounts() {
        let assessment = PredictiveReadinessService().calculateReadiness(
            stravaActivities: [], healthKitWorkouts: [], referenceDate: day(1), plannedDailyLoads: [day(0): 7])
        XCTAssertEqual(assessment.acuteLoad, 1.0, accuracy: 0.001)
        XCTAssertEqual(assessment.chronicLoad, 0.25, accuracy: 0.001)
    }

    // MARK: - History

    func testHistory_duplicateAndMissingRows() throws {
        ctx.insert(StoredDailyScore(date: day(-1), readinessScore: 50, dailyStrain: 1, workoutCount: 0, dailyLoad: 0))
        ctx.insert(StoredDailyScore(date: day(-1), readinessScore: 70, dailyStrain: 1, workoutCount: 1, dailyLoad: 3))
        ctx.insert(StoredDailyScore(date: day(-3), readinessScore: 60, dailyStrain: 1, workoutCount: 0, dailyLoad: 0))
        try ctx.save()

        let history = try repo.loadForecastHistory(context: ctx, now: noon).days
        XCTAssertEqual(history.map(\.date), [day(-3), day(-1)], "A missing day is left out, a duplicate counts once")
        XCTAssertEqual(history[1].load, 3, "A day's load is its highest row")
        XCTAssertEqual(history[1].score, 70, "and its score comes from that row")
    }

    func testHistory_rideOnAZeroLoadRowCounts() throws {
        insertRows(1...1, load: 0)
        insertRide("late-ride", daysAgo: 1, hours: 2)
        insertRows(2...2, load: 5)
        insertRide("no-row", daysAgo: 3, hours: 1)
        try ctx.save()

        let history = try repo.loadForecastHistory(context: ctx, now: noon).days
        XCTAssertEqual(history.map(\.load), [1, 5, 2], "The larger of row and rides; a row can go stale either way")
        XCTAssertEqual(history.map(\.score), [nil, 75, 75], "A day with no row has an unknown score, not a low one")
    }

    func testHistory_todayAndOldRowsAreLeftOut() throws {
        insertRows(0...0)
        insertRows(91...91)
        insertRows(90...90)
        try ctx.save()
        XCTAssertEqual(try repo.loadForecastHistory(context: ctx, now: noon).days.map(\.date), [day(-90)])
    }

    // MARK: - The plan

    func testStorePlan_under14Rows_isNil() throws {
        insertRows(1...13)
        try ctx.save()
        XCTAssertNil(try plan(start: 75))
    }

    func testStorePlan_returnsSevenDaysStartingToday() throws {
        insertRows(1...14)
        try ctx.save()
        XCTAssertEqual(try XCTUnwrap(plan(start: 75)).map(\.date), (0...6).map(day))
    }

    func testStorePlan_todaysRowIsNotHistory() throws {
        insertRows(1...13)
        insertRows(0...0, score: 20)
        try ctx.save()
        XCTAssertNil(try plan(start: 75), "Today's row is rewritten during the day and isn't a complete day")
    }

    func testStorePlan_rodeHardThisMorning() throws {
        insertRows(1...30)
        try ctx.save()
        XCTAssertEqual(try XCTUnwrap(plan(start: 81))[0].effort, .hard, "Fresh before the ride")

        insertRide("big-morning", daysAgo: 0, hours: 4)
        try ctx.save()
        let days = try XCTUnwrap(plan(start: 81, current: 60))
        XCTAssertEqual(days[0].effort, .rest)
        XCTAssertEqual(days[0].reason, "Rode hard today")
        XCTAssertNotEqual(days[1].effort, .hard)
    }

    func testStorePlan_overloadedRider_capsThenRelaxes() throws {
        insertRows(1...30, score: 88)
        insertRamp()
        try ctx.save()
        let days = try XCTUnwrap(plan(start: 88))
        XCTAssertEqual(days[0].effort, .easy, "ACWR above 1.5 caps today however recovered the rider is")
        XCTAssertEqual(days[0].reason, "Load ramping fast")
        // Not day 6 specifically: once the ceiling lifts the week alternates, and day 6 can be Easy by recovery.
        XCTAssertTrue(days[3...].contains { $0.effort < days[0].effort },
                      "The plan's lighter days bring the ratio down: \(days.map(\.effort))")
    }

    func testStorePlan_poorRecoveryOnWellLoadedRider_staysRest() throws {
        insertRows(1...30, score: 80)
        insertRamp()
        try ctx.save()
        XCTAssertEqual(try XCTUnwrap(plan(start: 40))[0].effort, .rest)
    }

    func testStorePlan_activeNotesAndPatterns() throws {
        insertRows(1...30)
        try ctx.save()

        let ignored = [
            CoachMemoryNote(context: "Morning rides", category: "Preference"),
            CoachMemoryNote(context: "Knee", category: "Injury", expiresAt: day(-1)),
            CoachMemoryNote(context: "Old knee", category: "Injury", isActive: false)
        ]
        XCTAssertEqual(try XCTUnwrap(plan(start: 81, memories: ignored))[0].effort, .hard)

        let injury = try XCTUnwrap(plan(start: 81, memories: [CoachMemoryNote(context: "Knee", category: "Injury")]))
        XCTAssertEqual(injury[0].effort, .easy)
        XCTAssertEqual(injury[0].reason, "Injury")

        for category in ["Travel", "Stress"] {
            let days = try XCTUnwrap(plan(start: 81, memories: [CoachMemoryNote(context: "x", category: category)]))
            XCTAssertEqual(days[0].effort, .moderate)
            XCTAssertEqual(days[0].reason, category)
        }

        let hrv = try XCTUnwrap(plan(start: 81, patterns: [.hrvPrecursor]))
        XCTAssertEqual(hrv[0].reason, "HRV dipping")
        XCTAssertEqual(try XCTUnwrap(plan(start: 81, risk: .high))[0].effort, .moderate)
        XCTAssertEqual(try XCTUnwrap(plan(start: 81, risk: .moderate))[0].effort, .hard)
        XCTAssertEqual(try XCTUnwrap(plan(start: 81, illness: .sick))[0].reason, "Sick")
    }

    func testFailedRead_keepsTheLastPlan() {
        struct ReadFailed: Error {}
        let todayPlan = [ReadinessRepository.ReadinessForecastDay(date: today, effort: .easy, reason: nil)]
        let oldPlan = [ReadinessRepository.ReadinessForecastDay(date: day(-1), effort: .easy, reason: nil)]
        typealias R = ReadinessRepository

        XCTAssertEqual(R.forecastAfterRead(.failure(ReadFailed()), last: todayPlan, now: noon)?.first?.effort, .easy)
        XCTAssertNil(R.forecastAfterRead(.failure(ReadFailed()), last: oldPlan, now: noon),
                     "Yesterday's plan would call yesterday Today")
        XCTAssertNil(R.forecastAfterRead(.success(nil), last: todayPlan, now: noon),
                     "A read that worked and found too little history isn't a failure")
        XCTAssertEqual(R.forecastAfterRead(.success(oldPlan), last: nil, now: noon)?.first?.date, day(-1))
    }

    // MARK: - The cache

    func testCache_workoutStoredAfterAnalysisChangesThePlan() throws {
        insertRows(1...30)
        try ctx.save()
        let before = try XCTUnwrap(plan(start: 81))
        let signature = repo.forecastInputSignature(context: ctx, now: noon)

        insertRide("synced-later", daysAgo: 0, hours: 4)
        try ctx.save()

        XCTAssertNotEqual(repo.forecastInputSignature(context: ctx, now: noon), signature)
        XCTAssertNotEqual(try XCTUnwrap(plan(start: 81))[0].reason, before[0].reason)
    }

    func testCache_zoneBackfillChangingLoadChangesTheSignature() throws {
        insertRows(1...30)
        let ride = insertRide("zones", daysAgo: 1, hours: 2)
        try ctx.save()
        let signature = repo.forecastInputSignature(context: ctx, now: noon)

        ride.powerZoneSecondsCSV = "0,0,0,0,7200,0,0"
        try ctx.save()
        XCTAssertNotEqual(repo.forecastInputSignature(context: ctx, now: noon), signature,
                          "Same count and dates, so the fingerprint can't see this")
    }

    func testCache_recomputedRowLoadChangesTheSignature() throws {
        insertRows(1...30)
        let row = StoredDailyScore(date: day(-31), readinessScore: 75, dailyStrain: 1, workoutCount: 0, dailyLoad: 0)
        ctx.insert(row)
        try ctx.save()
        let signature = repo.forecastInputSignature(context: ctx, now: noon)
        row.dailyLoad = 4
        try ctx.save()
        XCTAssertNotEqual(repo.forecastInputSignature(context: ctx, now: noon), signature)
    }

    func testCache_todaysRowRewriteDoesNotChangeTheSignature() throws {
        insertRows(1...30)
        let row = StoredDailyScore(date: today, readinessScore: 75, dailyStrain: 1, workoutCount: 0, dailyLoad: 0)
        ctx.insert(row)
        try ctx.save()
        let signature = repo.forecastInputSignature(context: ctx, now: noon)
        row.readinessScore = 40
        row.dailyLoad = 3
        try ctx.save()
        XCTAssertEqual(repo.forecastInputSignature(context: ctx, now: noon), signature,
                       "Analysis rewrites today's row itself; counting it would re-run analysis on every open")
    }

    // MARK: - Recovering days

    func testRecoveringDaysLeft() {
        typealias State = MasterCoachEngine.IllnessState
        func left(lastSickDaysAgo: Int) -> Int {
            State.recoveringDaysLeft([(start: day(-10), end: day(-lastSickDaysAgo))], now: noon, calendar: calendar)
        }
        XCTAssertEqual(left(lastSickDaysAgo: 1), 2)
        XCTAssertEqual(left(lastSickDaysAgo: 2), 1)
        XCTAssertEqual(left(lastSickDaysAgo: 3), 0)
        XCTAssertEqual(State.recoveringDaysLeft([(start: day(-2), end: nil)], now: noon, calendar: calendar), 0,
                       "Still sick isn't recovering")
        XCTAssertEqual(State.recoveringDaysLeft([], now: noon, calendar: calendar), 0)
    }

    // MARK: - Short nights

    func testShortSleepNights() {
        let usual = (3...20).map { HealthDataPoint(date: day(-$0), value: 8) }
        func nights(_ recent: [Double]) -> Int {
            let points = recent.enumerated().map { HealthDataPoint(date: day(-($0.offset + 1)), value: $0.element) }
            return ReadinessRepository.shortSleepNights(sleep: usual + points, now: noon, calendar: calendar)
        }
        XCTAssertEqual(nights([8, 8]), 0)
        XCTAssertEqual(nights([5, 8]), 1)
        XCTAssertEqual(nights([5, 5]), 2)
        XCTAssertEqual(nights([8, 5]), 0, "A short night before a good one is over")
        XCTAssertEqual(ReadinessRepository.shortSleepNights(sleep: [], now: noon, calendar: calendar), 0)
    }
}
