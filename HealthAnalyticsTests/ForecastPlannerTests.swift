//
//  ForecastPlannerTests.swift
//  HealthAnalyticsTests
//
//  The personal 7-day plan: what it learns about the rider, and the week it builds.
//

import XCTest
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
}
