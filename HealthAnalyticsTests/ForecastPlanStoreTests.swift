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

    // Generated by /ship coverage audit.
    // Value: protects=a row whose stored date drifted past midnight stays on its dateString day;
    // fails_when=history keys on row.date or the fetch's one-day lead-in is removed;
    // why_new=every other history fixture has date and dateString on the same day;
    // seam=none; no_claim=how rows drift in production (date is set by hand; in-memory store)
    func testHistory_driftedRowDateStaysOnItsDateStringDay() throws {
        let beforeWindow = StoredDailyScore(date: day(-90), readinessScore: 60, dailyStrain: 1, workoutCount: 0)
        beforeWindow.date = day(-90).addingTimeInterval(-3600)
        let intoToday = StoredDailyScore(date: day(-1), readinessScore: 65, dailyStrain: 1, workoutCount: 0)
        intoToday.date = today.addingTimeInterval(1800)
        ctx.insert(beforeWindow)
        ctx.insert(intoToday)
        try ctx.save()

        let history = try repo.loadForecastHistory(context: ctx, now: noon).days
        XCTAssertEqual(history.map(\.date), [day(-90), day(-1)])
        XCTAssertEqual(history.map(\.score), [60, 65])
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

    // MARK: - Coach agreement

    private func coachState(_ plan: ForecastPlan?, start: Int, current: Int) -> MasterCoachEngine.StateVector {
        ReadinessRepository.coachState(
            plan: plan?.days, profile: plan?.profile, startScore: start, morningScore: start, currentScore: current,
            acwr: 1.0, injuryRisk: .low, activePatterns: [], memories: [], illness: .none, now: noon)
    }

    func testCoachAgreement_todayAndTomorrowMatchThePlan() throws {
        insertRows(1...30)
        try ctx.save()
        let plan = try XCTUnwrap(repo.computeForecastPlan(
            modelContext: ctx, startScore: 63, currentScore: 63, illness: .none, activePatterns: [],
            memories: [], injuryRisk: .low, sleep: [], now: noon))
        let state = coachState(plan, start: 63, current: 63)

        XCTAssertEqual(state.todayEffort, plan.days[0].effort)
        XCTAssertEqual(plan.days[0].effort, .rest, "Fixture must make the word differ from what 63% alone would say")
        XCTAssertEqual(state.nextDayForecast, plan.days[1].coaching)
        XCTAssertEqual(state.startedLow, true)
        XCTAssertTrue(MasterCoachEngine.generateHeuristicMessage(state: state).contains("Prioritize rest"))
    }

    func testCoachAgreement_todaysRideMovesTheCoachWord() throws {
        insertRows(1...30)
        insertRide("big-morning", daysAgo: 0, hours: 4)
        try ctx.save()
        let plan = try XCTUnwrap(repo.computeForecastPlan(
            modelContext: ctx, startScore: 81, currentScore: 60, illness: .none, activePatterns: [],
            memories: [], injuryRisk: .low, sleep: [], now: noon))
        let state = coachState(plan, start: 81, current: 60)
        XCTAssertEqual(state.todayEffort, .rest)
        XCTAssertEqual(state.startedLow, false, "They started fresh; the ride brought them down")
        XCTAssertTrue(MasterCoachEngine.generateHeuristicMessage(state: state).contains("Rest for the remainder of the day."))
    }

    func testCoachState_withoutAPlanKeepsScoreBands() {
        let state = coachState(nil, start: 80, current: 80)
        XCTAssertNil(state.todayEffort)
        XCTAssertNil(state.nextDayForecast)
        XCTAssertNil(state.startedLow)
    }

    func testCoachState_aPlanFromAnotherDayIsNotToday() {
        let stale = [ReadinessRepository.ReadinessForecastDay(date: day(-1), effort: .hard, reason: nil)]
        let state = ReadinessRepository.coachState(
            plan: stale, profile: nil, startScore: 80, morningScore: 80, currentScore: 80,
            acwr: 1.0, injuryRisk: .low, activePatterns: [], memories: [], illness: .none, now: noon)
        XCTAssertNil(state.todayEffort)
    }

    // Generated by /ship coverage audit.
    // Value: protects=a plan kept across midnight gives the Coach the right days by date;
    // fails_when=coachState reads plan days by position instead of date;
    // why_new=the stale-plan test has one row, so it can't tell date lookup from position;
    // seam=none; no_claim=performFullAnalysis passes the kept plan here (singleton + HealthKit)
    func testCoachState_keptPlanIsReadByDateNotPosition() {
        let kept: [ReadinessRepository.ReadinessForecastDay] = [
            .init(date: day(-1), effort: .hard, reason: nil),
            .init(date: day(0), effort: .easy, reason: nil),
            .init(date: day(1), effort: .moderate, reason: nil)
        ]
        let state = ReadinessRepository.coachState(
            plan: kept, profile: nil, startScore: 80, morningScore: 80, currentScore: 80,
            acwr: 1.0, injuryRisk: .low, activePatterns: [], memories: [], illness: .none, now: noon)
        XCTAssertEqual(state.todayEffort, .easy)
        XCTAssertEqual(state.nextDayForecast, kept[2].coaching)
    }

    // MARK: - Forecast Check through the store

    // Generated by /ship coverage audit.
    // Value: protects=Forecast Check replays stored rows, and an empty store is a result, not a failed read;
    // fails_when=forecastCheck stops reading the store, shrinks its window under 26 days, or returns nil for no history;
    // why_new=replay is tested only on values, and forecastCheck had no test;
    // seam=none; no_claim=ForecastCheckView renders the result; a failed fetch (nil) isn't reachable here
    func testForecastCheck_replaysStoredRows() throws {
        let empty = try XCTUnwrap(repo.forecastCheck(modelContext: ctx, now: noon))
        XCTAssertEqual(empty.daysChecked, 0, "No history is a result; only a failed read is nil")

        insertRows(2...40, score: 70)
        insertRows(1...1, score: 40)
        try ctx.save()

        let result = try XCTUnwrap(repo.forecastCheck(modelContext: ctx, now: noon))
        XCTAssertEqual(result.daysChecked, 25, "Days -26 through -2 each have 14 days before them and a next morning")
        XCTAssertEqual(result.recentMisses.map(\.date), [day(-1)])
        XCTAssertEqual(result.recentMisses.first?.actual, .rest)
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

    // Generated by /ship coverage audit.
    // Value: protects=old sleep can't name short nights on today's card;
    // fails_when=the two-day staleness guard on the newest night is removed or shifted;
    // why_new=testShortSleepNights always has a night from yesterday, so the guard never runs;
    // seam=none; no_claim=HealthKit's night dating (points are dated by hand)
    func testShortSleepNights_staleSleepDoesNotCount() {
        let usual = (4...20).map { HealthDataPoint(date: day(-$0), value: 8) }
        func nights(lastShortNightDaysAgo: Int) -> Int {
            let points = usual + [HealthDataPoint(date: day(-lastShortNightDaysAgo), value: 5)]
            return ReadinessRepository.shortSleepNights(sleep: points, now: noon, calendar: calendar)
        }
        XCTAssertEqual(nights(lastShortNightDaysAgo: 3), 0, "Three days old says nothing about last night")
        XCTAssertEqual(nights(lastShortNightDaysAgo: 2), 1, "Two days old is the edge that still counts")
    }

    // MARK: - Final review fixes

    func testStorePlan_noTrainingHistory_isNotLockedByItsOwnPlan() throws {
        insertRows(1...30)
        try ctx.save()
        let days = try XCTUnwrap(plan(start: 81))
        XCTAssertFalse(days.contains { $0.reason == "Load ramping fast" }, "\(days.map(\.reason))")
        XCTAssertGreaterThan(days.filter { $0.effort == .hard }.count, 1, "\(days.map(\.effort))")
    }

    func testStorePlan_steadyThreeRidesAWeek_seesNoFalseRamp() throws {
        for offset in 1...35 {
            let load: Double? = offset % 7 == 1 || offset % 7 == 3 ? 2 : offset % 7 == 5 ? 4 : nil
            if let load { insertRide("steady-\(offset)", daysAgo: offset, hours: load) }
            if offset <= 30 { insertRows(offset...offset) }
        }
        try ctx.save()
        let days = try XCTUnwrap(plan(start: 75))
        XCTAssertFalse(days.contains { $0.reason == "Load ramping fast" }, "\(days.map(\.reason))")
    }

    /// The in-day score repays yesterday's fatigue as the hours pass. Stored rows never get that
    /// repayment, so reading today's word from it would drift upward with no new data.
    func testTodaysWordScore_noRideDoesNotClimbWithTheClock() {
        for hour in [8, 14, 22] {
            let now = calendar.date(byAdding: .hour, value: hour, to: today)!
            XCTAssertEqual(ReadinessRepository.forecastTodayScore(startScore: 70, workouts: [], stepExcessTSS: 0, now: now), 70)
        }
    }

    func testTodaysWordScore_aRideLowersItAndItRecoversThroughTheDay() {
        let ride = WorkoutData(from: StoredWorkout(id: "morning", type: .cycling, startDate: today.addingTimeInterval(7 * 3600),
                                                   duration: 3600, distance: nil, power: nil, energy: nil, hr: nil, source: "test"))
        func score(hour: Int) -> Int {
            ReadinessRepository.forecastTodayScore(startScore: 70, workouts: [ride], stepExcessTSS: 0,
                                                   now: calendar.date(byAdding: .hour, value: hour, to: today)!)
        }
        XCTAssertEqual(score(hour: 6), 70, "Not ridden yet")
        XCTAssertLessThan(score(hour: 9), 70)
        XCTAssertGreaterThan(score(hour: 20), score(hour: 9))
    }

    /// A background refresh must not take the screen away from someone reading it.
    func testRefreshOnlyBlocksTheScreenWhenThereIsNothingToShow() {
        XCTAssertTrue(ReadinessRepository.blocksContent(isAnalyzing: true, snapshotDate: nil, now: noon))
        XCTAssertFalse(ReadinessRepository.blocksContent(isAnalyzing: true, snapshotDate: noon, now: noon))
        XCTAssertFalse(ReadinessRepository.blocksContent(isAnalyzing: false, snapshotDate: nil, now: noon))
    }

    // MARK: - Ship review fixes

    func testStorePlan_oneRideAfterALayoff_isNotALoadRamp() throws {
        insertRows(1...30)
        insertRide("first-back", daysAgo: 0, hours: 0.5)
        try ctx.save()
        let days = try XCTUnwrap(plan(start: 81, current: 78))
        XCTAssertFalse(days.contains { $0.reason == "Load ramping fast" }, "\(days.map(\.reason))")
    }

    func testShortSleepNights_aGapBreaksTheRun() {
        let points = (6...20).map { HealthDataPoint(date: day(-$0), value: 8) }
            + [HealthDataPoint(date: day(-5), value: 5), HealthDataPoint(date: day(-1), value: 5)]
        XCTAssertEqual(ReadinessRepository.shortSleepNights(sleep: points, now: noon, calendar: calendar), 1)
    }

    /// Yesterday's paragraph shouldn't sit on screen as today's advice on the first open of the day.
    func testRefresh_blocksTheScreenWhenTheSnapshotIsFromAnotherDay() {
        XCTAssertTrue(ReadinessRepository.blocksContent(isAnalyzing: true, snapshotDate: day(-1), now: noon))
        XCTAssertFalse(ReadinessRepository.blocksContent(isAnalyzing: true, snapshotDate: noon, now: noon))
    }

    func testForcedBackfill_runsOncePerDayAndNeverOnAFailedRead() {
        typealias R = ReadinessRepository
        XCTAssertTrue(R.shouldForceScoreBackfill(lastAttempt: nil, readFailed: false, now: noon))
        XCTAssertFalse(R.shouldForceScoreBackfill(lastAttempt: today, readFailed: false, now: noon))
        XCTAssertTrue(R.shouldForceScoreBackfill(lastAttempt: day(-1), readFailed: false, now: noon))
        XCTAssertFalse(R.shouldForceScoreBackfill(lastAttempt: nil, readFailed: true, now: noon))
    }

    // MARK: - Absorption trend

    /// Ten one-hour rides rated 5, 31-58 days ago (outside the load limit's 28 days, so it stays
    /// open), then the last two rated `recent`.
    private func insertRatedRides(recent: Double?) {
        for (n, daysAgo) in stride(from: 31, through: 58, by: 3).enumerated() {
            insertRide("base-\(n)", daysAgo: daysAgo, hours: 1).effortRating = 5
        }
        insertRide("recent-1", daysAgo: 1, hours: 1).effortRating = recent
        insertRide("recent-2", daysAgo: 2, hours: 1).effortRating = recent
    }

    func testStorePlan_ratedRidesBuildTheTrend() throws {
        insertRows(1...30)
        insertRatedRides(recent: 5)
        try ctx.save()
        let usual = try XCTUnwrap(plan(start: 76, current: 75))

        for ride in try ctx.fetch(FetchDescriptor<StoredWorkout>()) where ride.id.hasPrefix("recent") { ride.effortRating = 8 }
        try ctx.save()
        let harder = try XCTUnwrap(plan(start: 76, current: 75))

        XCTAssertEqual(harder[0].effort, usual[0].effort, "Today's word doesn't move")
        XCTAssertTrue(zip(usual, harder).dropFirst().contains { $1.effort > $0.effort },
                      "usual \(usual.map(\.effort)) harder \(harder.map(\.effort))")
    }

    func testCache_newRatingChangesTheSignature() throws {
        insertRows(1...30)
        let ride = insertRide("rated-later", daysAgo: 1, hours: 1)
        try ctx.save()
        let before = repo.forecastInputSignature(context: ctx, now: noon)
        ride.effortRating = 7
        try ctx.save()
        XCTAssertNotEqual(repo.forecastInputSignature(context: ctx, now: noon), before)
    }

    func testAbsorptionSummary_readsStoredRatings() throws {
        insertRatedRides(recent: 8)
        insertRide("unrated", daysAgo: 3, hours: 1)
        try ctx.save()
        let summary = try XCTUnwrap(repo.absorptionSummary(modelContext: ctx, now: noon))
        XCTAssertEqual(summary.rides.first?.date, day(-1).addingTimeInterval(8 * 3600), "Newest first")
        XCTAssertEqual(summary.rides.first?.rating, 8)
        XCTAssertEqual(summary.rides.first?.expected, 5)
        XCTAssertEqual(summary.rides.first?.difference, 3)
        XCTAssertFalse(summary.rides.contains { $0.date == day(-3).addingTimeInterval(8 * 3600) }, "Unrated rides are left out")
        let w1 = pow(0.5, 1 / EffortAbsorption.halfLifeDays), w2 = pow(0.5, 2 / EffortAbsorption.halfLifeDays)
        XCTAssertEqual(summary.trend, 3 * (w1 + w2) / (w1 + w2 + EffortAbsorption.priorWeight), accuracy: 0.001)
        XCTAssertEqual(summary.rides.count, 2, "Rated rides from the last 30 days: days 1 and 2")
    }

    func testAbsorptionSummary_leavesOutOtherSports() throws {
        insertRatedRides(recent: 8)
        let run = StoredWorkout(id: "run", type: .running, startDate: day(-3).addingTimeInterval(8 * 3600),
                                duration: 3600, distance: nil, power: nil, energy: nil, hr: nil, source: "test")
        run.effortRating = 9
        ctx.insert(run)
        try ctx.save()
        let summary = try XCTUnwrap(repo.absorptionSummary(modelContext: ctx, now: noon))
        XCTAssertFalse(summary.rides.contains { $0.rating == 9 })
    }
}
