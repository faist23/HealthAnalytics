//
//  ForecastPlannerTests.swift
//  HealthAnalyticsTests
//
//  The personal 7-day plan: what it learns about the rider, and the week it builds.
//

import XCTest
import SwiftUI
@testable import HealthAnalytics

@MainActor
final class ForecastPlannerTests: XCTestCase {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    /// Ascending complete days ending yesterday, one per entry.
    private func history(_ days: [(score: Int?, load: Double)]) -> [ForecastHistoryDay] {
        days.enumerated().map { index, entry in
            ForecastHistoryDay(date: day(index - days.count), score: entry.score, load: entry.load)
        }
    }

    private func flat(_ count: Int, score: Int = 70, load: Double = 0) -> [(score: Int?, load: Double)] {
        Array(repeating: (score: score, load: load), count: count)
    }

    /// 60 days of 1.0-load rides at score 70, with a 6.0-load day every `every` days followed by
    /// the given mornings. Hard threshold is 1.25, so only the 6.0 days are hard.
    private func episodes(count: Int, every: Int = 8, mornings: [Int]) -> [(score: Int?, load: Double)] {
        var days = flat(60, load: 1.0)
        for n in 0..<count {
            let hardDay = 4 + n * every
            days[hardDay].load = 6.0
            for (offset, score) in mornings.enumerated() {
                days[hardDay + 1 + offset].score = score
            }
        }
        return days
    }

    private func learn(_ days: [(score: Int?, load: Double)]) -> ForecastProfile? {
        ForecastProfile.learn(history: history(days), today: today, calendar: calendar)
    }

    // MARK: - ForecastProfile.learn

    func testLearn_under14Scores_isNil() {
        XCTAssertNil(learn(flat(13)))
        XCTAssertNotNil(learn(flat(14)))
    }

    func testLearn_scoresOutside28Days_doNotCount() {
        let days = flat(13) + Array(repeating: (score: Int?.none, load: 0.0), count: 20) + flat(5)
        XCTAssertNil(learn(days), "Only 5 scored days fall inside the 28-day window")
    }

    func testLearn_normalAndSpreadAreRobust() throws {
        let profile = try XCTUnwrap(learn(flat(27) + [(score: 20, load: 0)]))
        XCTAssertEqual(profile.normal, 70)
        XCTAssertEqual(profile.spread, 4.0, "One bad day can't widen the spread; the floor applies")
    }

    func testBand_lowNormalRiderStillGetsHard() throws {
        let profile = try XCTUnwrap(learn(flat(28, score: 55)))
        XCTAssertEqual(profile.band(z: profile.z(58)), .hard)
        XCTAssertEqual(profile.band(z: profile.z(55)), .moderate)
        XCTAssertEqual(profile.band(z: profile.z(51)), .easy)
        XCTAssertEqual(profile.band(z: profile.z(45)), .rest)
    }

    func testHardDay_isTheTopQuarterOfTrainingLoads() throws {
        let loads = (1...8).map { (score: Int?.some(70), load: Double($0)) }
        let profile = try XCTUnwrap(learn(flat(20) + loads))
        XCTAssertEqual(profile.hardLoad, 6.25, accuracy: 0.001)
        XCTAssertEqual(profile.moderateLoad, 4.5, accuracy: 0.001)
        XCTAssertEqual(profile.easyLoad, 2.75, accuracy: 0.001)
    }

    func testUniformRider_ridesAreNotAllHard() throws {
        let profile = try XCTUnwrap(learn(flat(30, load: 1.0)))
        XCTAssertFalse(profile.isHard(load: 1.0))
        XCTAssertTrue(profile.isHard(load: 1.25))
    }

    func testNoTrainingHistory_usesFallbacks() throws {
        let profile = try XCTUnwrap(learn(flat(30)))
        XCTAssertEqual(profile.hardLoad, 3.0)
        XCTAssertEqual(profile.moderateLoad, 1.5)
        XCTAssertEqual(profile.easyLoad, 0.75)
        XCTAssertEqual(profile.typicalLoad(.rest), 0)
        XCTAssertEqual(profile.recoveryDays, 1)
        XCTAssertEqual(profile.dip, 1.0)
    }

    func testRecovery_slowHistoryLearnsTwoDays() throws {
        let profile = try XCTUnwrap(learn(episodes(count: 6, mornings: [60, 62])))
        XCTAssertEqual(profile.episodeCount, 6)
        XCTAssertEqual(profile.recoveryDays, 2)
        XCTAssertEqual(profile.rho, 0.6)
        XCTAssertEqual(profile.dip, 2.0, "Next-morning z of -2.5 clamps to the 2.0 limit")
    }

    func testRecovery_fastHistoryLearnsOneDay() throws {
        let profile = try XCTUnwrap(learn(episodes(count: 6, mornings: [])))
        XCTAssertEqual(profile.recoveryDays, 1)
        XCTAssertEqual(profile.rho, 0.4)
        XCTAssertEqual(profile.dip, 0.5)
    }

    func testRecovery_threeEpisodesUsesTheDefault() throws {
        let profile = try XCTUnwrap(learn(episodes(count: 3, mornings: [60, 62])))
        XCTAssertEqual(profile.episodeCount, 3)
        XCTAssertEqual(profile.recoveryDays, 1)
        XCTAssertEqual(profile.dip, 1.0)
    }

    func testRecovery_backToBackHardDaysAddNoEpisode() throws {
        var days = flat(60, load: 1.0)
        for start in [4, 12, 20, 28, 36] {
            days[start].load = 6.0
            days[start + 1].load = 6.0
        }
        XCTAssertEqual(try XCTUnwrap(learn(days)).episodeCount, 0)
    }

    func testRecovery_nextHardDayBeforeReturnSkipsTheEpisode() throws {
        var days = flat(60, load: 1.0)
        days[4].load = 6.0
        days[5].score = 60      // still down
        days[6].load = 6.0      // hard again before returning
        XCTAssertEqual(try XCTUnwrap(learn(days)).episodeCount, 1, "Only the day-6 episode stands")
    }

    func testRecovery_learnedTimeIsClampedToThree() throws {
        let profile = try XCTUnwrap(learn(episodes(count: 6, mornings: [60, 60, 60, 60, 60])))
        XCTAssertEqual(profile.recoveryDays, 3)
        XCTAssertEqual(profile.rho, 0.75)
    }

    func testRecovery_missingNextDayRowAddsNoEpisode() throws {
        var days = flat(60, load: 1.0)
        days[4].load = 6.0
        days[5].score = nil
        XCTAssertEqual(try XCTUnwrap(learn(days)).episodeCount, 0)
    }

    // Generated by /ship coverage audit.
    // Value: protects=a hard day whose return window runs past the last complete day adds no episode;
    // fails_when=the missing-day guard counts an unseen outcome as recovered or as a full window;
    // why_new=the existing test covers a nil next-morning score only, not a window off the history's end;
    // seam=none; no_claim=whether real rider history has such episodes (synthetic days)
    func testRecovery_returnWindowPastTheHistoryAddsNoEpisode() throws {
        var days = flat(60, load: 1.0)
        days[57].load = 6.0
        days[58].score = 60
        days[59].score = 60     // still down, and no later day to show the outcome
        XCTAssertEqual(try XCTUnwrap(learn(days)).episodeCount, 0)
    }

    // MARK: - ForecastPlanner.plan
    //
    // A rider with normal 75 and spread 6, so a score of 75 + 6z sits at z. Hard load 3.0.

    private typealias Effort = ReadinessRepository.ForecastEffort

    private var noon: Date { calendar.date(byAdding: .hour, value: 12, to: today)! }

    private func profile(normal: Double = 75, recoveryDays: Int = 1, dip: Double = 1.0) -> ForecastProfile {
        ForecastProfile(normal: normal, spread: 6, hardLoad: 3, moderateLoad: 1.5, easyLoad: 0.75,
                        dip: dip, recoveryDays: recoveryDays, episodeCount: 0)
    }

    private func score(z: Double, normal: Double = 75) -> Int { Int((normal + 6 * z).rounded()) }

    private func input(z: Double, currentZ: Double? = nil, rode: Double = 0, profile p: ForecastProfile? = nil,
                       rules: HardDayRules = .under60, hardDaysAgo: [Int] = [],
                       acwr: @escaping (Date, [Date: Double]) -> Double = { _, _ in 1.0 }) -> ForecastPlanInput {
        let p = p ?? profile()
        var input = ForecastPlanInput(now: noon, startScore: score(z: z, normal: p.normal),
                                      currentScore: score(z: currentZ ?? z, normal: p.normal),
                                      rodeLoadToday: rode,
                                      recentLoads: hardDaysAgo.sorted(by: >).map {
                                          ForecastHistoryDay(date: day(-$0), score: 70, load: 5)
                                      },
                                      profile: p, projectedACWR: acwr)
        input.hardDayRules = rules
        return input
    }

    private func plan(_ input: ForecastPlanInput) -> [ReadinessRepository.ReadinessForecastDay] {
        ForecastPlanner.plan(input, calendar: calendar)
    }

    private func assertNoAdjacentHard(_ days: [ReadinessRepository.ReadinessForecastDay], line: UInt = #line) {
        for (a, b) in zip(days, days.dropFirst()) {
            XCTAssertFalse(a.effort == .hard && b.effort == .hard, "Two Hard days in a row: \(days.map(\.effort))", line: line)
        }
    }

    func testPlan_isSevenDaysStartingToday() {
        let days = plan(input(z: 0))
        XCTAssertEqual(days.map(\.date), (0...6).map(day))
    }

    func testCraigsWeek() {
        let days = plan(input(z: -2))
        XCTAssertEqual(days[0].effort, .rest)
        XCTAssertEqual(days[1].effort, .moderate)
        XCTAssertEqual(days[2].effort, .hard)
    }

    func testNeverTwoHardDaysInARow_byDefault() {
        let days = plan(input(z: 1))
        XCTAssertEqual(days[0].effort, .hard)
        assertNoAdjacentHard(days)
    }

    func testSlowRecoverer_twoNonHardDaysAfterEachHard() {
        let days = plan(input(z: 0, profile: profile(recoveryDays: 2, dip: 1.5)))
        let hard = days.indices.filter { days[$0].effort == .hard }
        XCTAssertFalse(hard.isEmpty)
        for (a, b) in zip(hard, hard.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 3, "\(days.map(\.effort))")
        }
    }

    func testFastRecoverer_oneNonHardDayIsEnough() {
        let days = plan(input(z: 0, profile: profile(recoveryDays: 1, dip: 0.5)))
        let hard = days.indices.filter { days[$0].effort == .hard }
        XCTAssertTrue(zip(hard, hard.dropFirst()).contains { $1 - $0 == 2 }, "\(days.map(\.effort))")
    }

    func testBackToBackRule_holdsForTheFastestLearnedRider() {
        assertNoAdjacentHard(plan(input(z: 2, profile: profile(recoveryDays: 1, dip: 0.5))))
    }

    func testLowNormalRider_getsModerateAndHard() {
        let efforts = plan(input(z: 0, profile: profile(normal: 55))).map(\.effort)
        XCTAssertTrue(efforts.contains(.moderate))
        XCTAssertTrue(efforts.contains(.hard))
    }

    func testRodeHardToday() {
        let days = plan(input(z: 1, currentZ: -2, rode: 3))
        XCTAssertEqual(days[0].effort, .rest)
        XCTAssertEqual(days[0].reason, "Rode hard today")
        XCTAssertNotEqual(days[1].effort, .hard)
    }

    func testTodaysWord_followsTheInDayScore() {
        let lower = plan(input(z: 1, currentZ: -1, rode: 3))
        let later = plan(input(z: 1, currentZ: 0, rode: 3))
        XCTAssertEqual(lower[0].effort, .easy)
        XCTAssertEqual(later[0].effort, .moderate, "The word recovers as the day goes on")
        XCTAssertEqual(lower.dropFirst().map(\.effort), later.dropFirst().map(\.effort))
    }

    func testBigRideToday_lowersTomorrowMoreThanASmallRide() {
        let small = plan(input(z: 1, rode: 1))
        let big = plan(input(z: 1, rode: 9))
        XCTAssertGreaterThan(big[1].effort, small[1].effort)
    }

    func testRodeToday_smallRide() {
        XCTAssertEqual(plan(input(z: 0, rode: 0.6))[0].reason, "Rode today")
        XCTAssertNil(plan(input(z: 0, rode: 0.3))[0].reason, "A warmup isn't a ride worth naming")
    }

    func testYesterdaysHardRide_capsToday() {
        let base = input(z: 1)
        let yesterday = day(-1)
        let days = plan(ForecastPlanInput(now: base.now, startScore: base.startScore, currentScore: base.currentScore,
                                          rodeLoadToday: 0,
                                          recentLoads: [ForecastHistoryDay(date: yesterday, score: 70, load: 5)],
                                          profile: base.profile, projectedACWR: base.projectedACWR))
        XCTAssertEqual(days[0].effort, .easy)
        XCTAssertEqual(days[0].reason, "Still recovering from \(yesterday.formatted(.dateTime.weekday(.wide)))")
    }

    func testLoadCeiling_capsAndRelaxes() {
        let day3End = day(4)
        let days = plan(input(z: 1, acwr: { [self] close, _ in
            close <= day(3) ? 1.6 : close == day3End ? 1.4 : 1.0
        }))
        for offset in 0...2 {
            XCTAssertGreaterThanOrEqual(days[offset].effort, .easy)
            XCTAssertEqual(days[offset].reason, "Load ramping fast")
        }
        XCTAssertEqual(days[3].effort, .moderate)
        XCTAssertTrue(days[4...].contains { $0.effort == .hard }, "\(days.map(\.effort))")
    }

    func testLoadCeiling_isACeilingNeverAFloor() {
        XCTAssertEqual(plan(input(z: -2, acwr: { _, _ in 1.6 }))[0].effort, .rest)
    }

    func testLoadCeiling_day0ClosesNow_laterDaysCarryThePlan() {
        var calls: [(close: Date, planned: [Date: Double])] = []
        let days = plan(input(z: 0, rode: 1.0, acwr: { close, planned in
            calls.append((close, planned))
            return 1.0
        }))
        XCTAssertEqual(calls[0].close, noon)
        XCTAssertTrue(calls[0].planned.isEmpty)
        XCTAssertEqual(calls[1].close, day(2))
        XCTAssertEqual(calls[1].planned[day(0)] ?? -1, max(0, 1.5 - 1.0), accuracy: 0.001,
                       "Today's ride is in the workouts already; only the rest of the suggested load is planned")
        XCTAssertEqual(calls[2].planned.count, 2)
        XCTAssertEqual(days[0].effort, .moderate)
    }

    func testHRVPrecursor_capsTodayAndTomorrow() {
        var i = input(z: 1)
        i.hrvPrecursorActive = true
        let days = plan(i)
        XCTAssertEqual(days[0].effort, .easy)
        XCTAssertEqual(days[1].effort, .easy)
        XCTAssertEqual(days[0].reason, "HRV dipping")
        XCTAssertEqual(days[2].effort, .hard)
    }

    func testInjuryRisk_capsTodayAndTomorrow() {
        var i = input(z: 1)
        i.injuryRiskElevated = true
        let days = plan(i)
        XCTAssertEqual(days[0].effort, .moderate)
        XCTAssertEqual(days[1].effort, .moderate)
        XCTAssertEqual(days[0].reason, "Load ramping fast")
        XCTAssertEqual(days[2].effort, .hard)
    }

    func testSick_isAllRest() {
        var i = input(z: 2)
        i.illness = .sick
        let days = plan(i)
        XCTAssertEqual(days.map(\.effort), Array(repeating: Effort.rest, count: 7))
        XCTAssertEqual(days.map(\.reason), Array(repeating: "Sick", count: 7))
    }

    func testRecovering_daysLeftCapThenFree() {
        var i = input(z: 1)
        i.illness = .recovering(daysLeft: 2)
        let days = plan(i)
        XCTAssertEqual(days[0].effort, .easy)
        XCTAssertEqual(days[1].effort, .easy)
        XCTAssertEqual(days[0].reason, "Easing back after illness")
        XCTAssertEqual(days[1].reason, "Easing back after illness")
        XCTAssertEqual(days[2].effort, .hard)
        XCTAssertNotEqual(days[2].reason, "Easing back after illness")
    }

    func testNoteCaps_openEndedCapsTheWholeWeek() {
        var i = input(z: 1)
        i.noteCaps = [ForecastNoteCap(cap: .easy, reason: "Injury", until: nil)]
        let days = plan(i)
        XCTAssertTrue(days.allSatisfy { $0.effort >= .easy }, "\(days.map(\.effort))")
        XCTAssertTrue(days.allSatisfy { $0.effort == .rest || $0.reason == "Injury" }, "\(days.map(\.reason))")
    }

    func testNoteCaps_endWithTheNote() {
        var i = input(z: 1)
        let tomorrowNoon = calendar.date(byAdding: .hour, value: 12, to: day(1))!
        i.noteCaps = [ForecastNoteCap(cap: .moderate, reason: "Travel", until: tomorrowNoon)]
        let days = plan(i)
        XCTAssertEqual(days[0].effort, .moderate)
        XCTAssertEqual(days[0].reason, "Travel")
        XCTAssertEqual(days[1].effort, .moderate)
        XCTAssertEqual(days[2].effort, .hard)
    }

    func testMostRestrictiveCapWins_reasonNamesIt() {
        var i = input(z: 1, acwr: { _, _ in 1.4 })
        i.noteCaps = [ForecastNoteCap(cap: .easy, reason: "Injury", until: nil)]
        let days = plan(i)
        XCTAssertEqual(days[0].effort, .easy)
        XCTAssertEqual(days[0].reason, "Injury")
    }

    func testReason_lowRecoveryToday() {
        var i = input(z: -2)
        i.shortSleepNights = 2
        XCTAssertEqual(plan(i)[0].reason, "Two short nights")
        i.shortSleepNights = 1
        XCTAssertEqual(plan(i)[0].reason, "Short sleep")
        i.shortSleepNights = 0
        XCTAssertEqual(plan(i)[0].reason, "Low recovery")
    }

    func testReason_bouncingBack() {
        XCTAssertEqual(plan(input(z: -2))[1].reason, "Bouncing back after rest")
    }

    func testReason_nilWhenTheDayIsObvious() {
        XCTAssertNil(plan(input(z: 0))[0].reason)
    }

    func testNeverSevenRestDays_withoutIllness() {
        var i = input(z: 0, profile: profile(recoveryDays: 3, dip: 2.0))
        i = ForecastPlanInput(now: i.now, startScore: 0, currentScore: 0, rodeLoadToday: 0, recentLoads: [],
                              profile: i.profile, projectedACWR: i.projectedACWR)
        let days = plan(i)
        XCTAssertTrue(days[...4].contains { $0.effort != .rest }, "\(days.map(\.effort))")
    }

    // MARK: - Hard-day rules by age

    private func efforts(_ days: [ReadinessRepository.ReadinessForecastDay]) -> String {
        days.map(\.effort.label).joined(separator: " ")
    }

    func testDayAfterHard_isAtMostEasy_atEveryAge() {
        for rules in [HardDayRules.under60, .from60] {
            let days = plan(input(z: 2, rules: rules))
            XCTAssertEqual(days[0].effort, .hard)
            XCTAssertGreaterThanOrEqual(days[1].effort, .easy, efforts(days))
        }
    }

    func testFrom60_twoDaysBetweenHards_andTwoAWeek() {
        let days = plan(input(z: 2, profile: profile(recoveryDays: 1, dip: 0.5), rules: .from60))
        let hard = days.indices.filter { days[$0].effort == .hard }
        XCTAssertEqual(hard.count, 2, efforts(days))
        guard hard.count == 2 else { return }
        XCTAssertGreaterThanOrEqual(hard[1] - hard[0], 3, efforts(days))
        XCTAssertGreaterThanOrEqual(days[hard[0] + 2].effort, .moderate, efforts(days))
    }

    func testUnder60_threeAWeek() {
        // A fast recoverer (dip 0.5), so recovery alone would allow Hard every other day: 0, 2, 4, 6.
        let days = plan(input(z: 2, profile: profile(recoveryDays: 1, dip: 0.5), rules: .under60))
        XCTAssertEqual(days.filter { $0.effort == .hard }.count, 3, efforts(days))
    }

    func testLearnedRecoveryLongerThanTheAgeFloorWins() {
        let days = plan(input(z: 2, profile: profile(recoveryDays: 3, dip: 0.5), rules: .from60))
        let hard = days.indices.filter { days[$0].effort == .hard }
        XCTAssertGreaterThanOrEqual(hard.count, 2, efforts(days))
        for (a, b) in zip(hard, hard.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 4, efforts(days)) }
    }

    func testFrom60_twoHardRidesThisWeek_holdHardWithTheReason() {
        // Hard rides 5 and 3 days ago: day 0 and day 1 still see both in their trailing 6 days.
        let days = plan(input(z: 2, rules: .from60, hardDaysAgo: [5, 3]))
        XCTAssertEqual(days[0].effort, .moderate)
        XCTAssertEqual(days[0].reason, "Enough hard days this week")
        XCTAssertNotEqual(days[1].effort, .hard)
        XCTAssertEqual(days[2].effort, .hard, efforts(days))   // the ride 5 days ago is now 7 back
    }

    func testRodeHardYesterdayAndTheDayBefore_at65() {
        let days = plan(input(z: 2, rules: .from60, hardDaysAgo: [2, 1]))
        XCTAssertGreaterThanOrEqual(days[0].effort, .easy, efforts(days))
        XCTAssertEqual(days[0].reason, "Still recovering from \(day(-1).formatted(.dateTime.weekday(.wide)))")
        XCTAssertGreaterThanOrEqual(days[1].effort, .moderate, efforts(days))
    }

    func testMoreHardDaysRiddenThanTheLimit_at60() {
        let days = plan(input(z: 2, rules: .from60, hardDaysAgo: [5, 3, 1]))
        // Trailing 6 days hold fewer than 2 only from day 4 (the rides 5 and 3 days ago have left).
        XCTAssertFalse(days[0...3].contains { $0.effort == .hard }, efforts(days))
    }

    func testHardRideTodayCountsTowardTheWeek_at65() {
        let days = plan(input(z: 2, rode: 5, rules: .from60, hardDaysAgo: [3]))
        XCTAssertFalse(days[1...3].contains { $0.effort == .hard }, efforts(days))
    }

    func testStricterCapStillWins() {
        var i = input(z: 2, rules: .from60)
        i.illness = .sick
        XCTAssertTrue(plan(i).allSatisfy { $0.effort == .rest })
    }

    // MARK: - The card

    func testRowTitle_todayAndWeekday() {
        XCTAssertEqual(ForecastPlanCard.rowTitle(for: today, now: noon, calendar: calendar), "Today")
        XCTAssertEqual(ForecastPlanCard.rowTitle(for: day(1), now: noon, calendar: calendar),
                       day(1).formatted(.dateTime.weekday(.wide)))
    }

    func testRowTitle_staleFirstDayIsNotToday() {
        XCTAssertEqual(ForecastPlanCard.rowTitle(for: day(-1), now: noon, calendar: calendar),
                       day(-1).formatted(.dateTime.weekday(.wide)))
    }

    func testEffortWordAndLight_matchTheSpecTable() {
        XCTAssertEqual(Effort.rest.word, "Rest")
        XCTAssertEqual(Effort.easy.word, "Easy")
        XCTAssertEqual(Effort.moderate.word, "Moderate")
        XCTAssertEqual(Effort.hard.word, "Hard")
        XCTAssertEqual(Effort.rest.light, Color.statusWarning)
        XCTAssertEqual(Effort.easy.light, Color.statusMonitoring)
        XCTAssertEqual(Effort.moderate.light, Color.statusOptimal)
        XCTAssertEqual(Effort.hard.light, Color.statusOptimal)
    }

    func testAccessibilityLabel_readsTheWholeRow() {
        let row = ReadinessRepository.ReadinessForecastDay(date: today, effort: .moderate, reason: "Rode today")
        XCTAssertEqual(ForecastPlanCard.accessibilityLabel(for: row, now: noon, calendar: calendar), "Today, Moderate, Rode today")
        let plain = ReadinessRepository.ReadinessForecastDay(date: today, effort: .easy, reason: nil)
        XCTAssertEqual(ForecastPlanCard.accessibilityLabel(for: plain, now: noon, calendar: calendar), "Today, Easy")
    }

    // MARK: - Final review fixes

    func testRideDayFollowedByARise_isNotCalledBouncingBack() {
        let days = plan(input(z: 1, currentZ: -2, rode: 1.0))
        XCTAssertEqual(days[0].effort, .rest)
        XCTAssertLessThan(days[1].effort, days[0].effort, "Fixture must move up, or the test proves nothing")
        XCTAssertNotEqual(days[1].reason, "Bouncing back after rest", "They rode; they didn't rest")
    }

    func testHardRideToday_neverLeavesHardOnTheCard() {
        let days = plan(input(z: 1, currentZ: 1, rode: 3))
        XCTAssertEqual(days[0].effort, .moderate)
        XCTAssertEqual(days[0].reason, "Rode hard today")
    }

    func testLearn_trainingDayShareCountsThe28DayWindow() throws {
        var days = flat(40)
        for index in stride(from: 12, to: 40, by: 4) { days[index].load = 2 }
        XCTAssertEqual(try XCTUnwrap(learn(days)).trainingDayShare, 7.0 / 28.0, accuracy: 0.001)
    }

    func testPlannedLoad_scalesWithHowOftenTheRiderTrains() {
        var p = profile()
        p.trainingDayShare = 0.5
        var planned: [Date: Double] = [:]
        _ = plan(input(z: 0, profile: p, acwr: { _, loads in
            planned = loads
            return 1.0
        }))
        XCTAssertEqual(planned[day(0)] ?? -1, 1.5 * 0.5, accuracy: 0.001, "A Moderate day at half the rider's usual frequency")
    }

    // MARK: - Ship review fixes

    func testRodeToday_doesNotHideABindingCap() {
        var i = input(z: 1, rode: 0.6)
        i.noteCaps = [ForecastNoteCap(cap: .easy, reason: "Injury", until: nil)]
        XCTAssertEqual(plan(i)[0].reason, "Injury")
    }

    /// One warmup after a layoff reads as ACWR 4.0, a ratio with no real chronic load behind it.
    func testLoadCeiling_heldOpenWithoutEnoughRecentTraining() {
        var p = profile()
        p.trainingDayShare = 0
        let days = plan(input(z: 1, rode: 0.2, profile: p, acwr: { _, _ in 4.0 }))
        XCTAssertFalse(days.contains { $0.reason == "Load ramping fast" }, "\(days.map(\.reason))")
        XCTAssertEqual(days[0].effort, .hard)
    }

    func testLoadCeiling_appliesOnceTheRiderTrainsRegularly() {
        var p = profile()
        p.trainingDayShare = 4.0 / 28.0
        XCTAssertEqual(plan(input(z: 1, profile: p, acwr: { _, _ in 1.6 }))[0].reason, "Load ramping fast")
    }

    // MARK: - Ride cost trend

    private func shifted(_ trend: Double, z: Double, currentZ: Double? = nil) -> ForecastPlanInput {
        var i = input(z: z, currentZ: currentZ)
        i.rideCostTrend = trend
        return i
    }

    func testShift_harderTrendLowersTheComingDays() {
        let usual = plan(shifted(0, z: 1))
        let harder = plan(shifted(2, z: 1))
        XCTAssertTrue(zip(usual, harder).dropFirst().allSatisfy { $1.effort >= $0.effort }, "\(harder.map(\.effort))")
        XCTAssertTrue(zip(usual, harder).dropFirst().contains { $1.effort > $0.effort }, "\(harder.map(\.effort))")
    }

    /// From z -3 tomorrow is Moderate as usual and Hard with the lift. (From z -1 tomorrow is Hard
    /// either way, and the day after a Hard day is Easy whatever the trend.)
    func testShift_easierTrendLiftsThem() {
        let usual = plan(shifted(0, z: -3))
        let easier = plan(shifted(-2, z: -3))
        XCTAssertTrue(zip(usual, easier).dropFirst().contains { $1.effort < $0.effort }, "\(easier.map(\.effort))")
    }

    func testShift_neverChangesTodaysWord() {
        XCTAssertEqual(plan(shifted(4, z: 1))[0].effort, plan(shifted(0, z: 1))[0].effort)
        XCTAssertEqual(plan(shifted(-4, z: -2))[0].effort, plan(shifted(0, z: -2))[0].effort)
    }

    func testShift_easierNeverLiftsPastACap() {
        var hrv = shifted(-4, z: 1)
        hrv.hrvPrecursorActive = true
        XCTAssertGreaterThanOrEqual(plan(hrv)[1].effort, .easy)
        var note = shifted(-4, z: 1)
        note.noteCaps = [ForecastNoteCap(cap: .easy, reason: "Injury", until: nil)]
        XCTAssertTrue(plan(note).allSatisfy { $0.effort >= .easy })
        let days = plan(shifted(-4, z: 2))
        for (a, b) in zip(days, days.dropFirst()) {
            XCTAssertFalse(a.effort == .hard && b.effort == .hard, "Recovery time still holds: \(days.map(\.effort))")
        }
    }

    /// Start z 0.3 with today at Moderate: tomorrow is Hard as usual, and a full shift (rides 2 points
    /// harder) moves it to Easy.
    func testShift_reasonNamesTheTrendOnlyWhenItMovedTheDay() {
        let usual = plan(shifted(0, z: 0.3, currentZ: 0))
        let harder = plan(shifted(2, z: 0.3, currentZ: 0))
        XCTAssertEqual(usual[1].effort, .hard)
        XCTAssertEqual(harder[1].effort, .easy)
        XCTAssertEqual(harder[1].reason, "Rides costing more than usual")
        XCTAssertFalse(usual.contains { $0.reason?.hasPrefix("Rides costing") == true })
        // From z -1.4 (today Easy) tomorrow is Moderate as usual and Hard with the lift.
        let easier = plan(shifted(-2, z: -1.4, currentZ: -1.4))
        XCTAssertEqual(easier[1].effort, .hard)
        XCTAssertEqual(easier[1].reason, "Rides costing less than usual", "\(easier.map(\.reason))")
    }

    func testShift_zeroTrendChangesNothing() {
        let a = plan(input(z: 0.5))
        let b = plan(shifted(0, z: 0.5))
        XCTAssertEqual(a.map(\.effort), b.map(\.effort))
        XCTAssertEqual(a.map(\.reason), b.map(\.reason))
    }

    /// A hard ride today puts an Easy recovery cap on tomorrow. With z 3, tomorrow's band is Hard
    /// as usual and Moderate when rides feel 1 point harder: the same word, which the cap sets.
    func testShift_reasonKeepsTheCapWhenTheCapAlreadySetTheWord() {
        let usual = plan(ForecastPlanInput(now: noon, startScore: score(z: 3), currentScore: score(z: 3), rodeLoadToday: 3,
                                           recentLoads: [], profile: profile(), rideCostTrend: 0, projectedACWR: { _, _ in 1 }))
        let harder = plan(ForecastPlanInput(now: noon, startScore: score(z: 3), currentScore: score(z: 3), rodeLoadToday: 3,
                                            recentLoads: [], profile: profile(), rideCostTrend: 1, projectedACWR: { _, _ in 1 }))
        XCTAssertEqual(usual[1].effort, harder[1].effort)
        XCTAssertEqual(harder[1].reason, usual[1].reason, "Same word, so the cap still explains it")
    }

    /// A hard ride today caps tomorrow at Easy. When rides feel 2 points harder, the shift
    /// (1 spread) can take tomorrow past that cap to Rest: the feel set the word, so
    /// it gives the reason, not the looser cap.
    func testShift_feelPastACapGivesTheFeelReason() {
        func day1(_ trend: Double, z: Double) -> ReadinessRepository.ReadinessForecastDay {
            plan(ForecastPlanInput(now: noon, startScore: score(z: z), currentScore: score(z: z), rodeLoadToday: 3,
                                   recentLoads: [], profile: profile(), rideCostTrend: trend, projectedACWR: { _, _ in 1 }))[1]
        }
        let cases = stride(from: -1.0, through: 4.0, by: 1.0 / 6).filter { z in
            day1(0, z: z).effort == .easy && day1(2, z: z).effort == .rest
        }
        XCTAssertFalse(cases.isEmpty, "Some start puts tomorrow under the Easy cap as usual and at Rest when harder")
        for z in cases {
            XCTAssertEqual(day1(2, z: z).reason, "Rides costing more than usual", "start z \(z)")
        }
    }
}
