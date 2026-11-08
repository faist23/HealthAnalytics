//
//  EffortCheckTests.swift
//  HealthAnalyticsTests
//
//  The read-only check behind the effort-score idea: do Craig's own rides carry a rating he gave?
//

import XCTest
@testable import HealthAnalytics

final class EffortCheckTests: XCTestCase {

    private func workout(_ source: String, cycling: Bool = true, rated: Double? = nil,
                         estimated: Double? = nil, ratedBy: String? = nil, daysAgo: Int = 1) -> EffortCheckWorkout {
        EffortCheckWorkout(date: Date().addingTimeInterval(Double(-daysAgo) * 86_400), source: source,
                           isCycling: cycling, minutes: 60, rated: rated, ratedBy: rated == nil ? nil : (ratedBy ?? "Fitness"),
                           estimated: estimated)
    }

    func testSummary_countsRatedAndEstimatedApart() {
        let summary = EffortCheckSummary.summarize([
            workout("Strava", rated: 6),
            workout("Strava", estimated: 5),
            workout("Strava", rated: 7, estimated: 6),
            workout("Workout", cycling: false, rated: 3)
        ])
        XCTAssertEqual(summary.workouts, 4)
        XCTAssertEqual(summary.rated, 3)
        XCTAssertEqual(summary.estimated, 2)
        XCTAssertEqual(summary.rides, 3)
        XCTAssertEqual(summary.ridesRated, 2)
    }

    func testSummary_groupsBySourceMostWorkoutsFirst() {
        let summary = EffortCheckSummary.summarize([
            workout("Workout", estimated: 4),
            workout("Strava", rated: 6),
            workout("Strava"),
            workout("Strava", rated: 5)
        ])
        XCTAssertEqual(summary.sources.map(\.name), ["Strava", "Workout"])
        XCTAssertEqual(summary.sources[0], EffortCheckSummary.Source(name: "Strava", workouts: 3, rated: 2, estimated: 0))
        XCTAssertEqual(summary.sources[1], EffortCheckSummary.Source(name: "Workout", workouts: 1, rated: 0, estimated: 1))
    }

    /// An estimate is Apple's guess from heart rate, not how the ride felt, so it never counts as rated.
    func testVerdict_estimatesAloneMeanNoRatedRides() {
        let summary = EffortCheckSummary.summarize([workout("Workout", estimated: 6), workout("Strava")])
        XCTAssertEqual(summary.verdict, .noRatedRides)
    }

    func testVerdict_someRidesRated() {
        let summary = EffortCheckSummary.summarize([workout("Strava", rated: 6), workout("Strava")])
        XCTAssertEqual(summary.verdict, .someRidesRated(rated: 1, rides: 2))
    }

    func testVerdict_allRidesRated() {
        let summary = EffortCheckSummary.summarize([workout("Strava", rated: 6), workout("Workout", cycling: false)])
        XCTAssertEqual(summary.verdict, .allRidesRated(rides: 1))
    }

    func testVerdict_noRides() {
        XCTAssertEqual(EffortCheckSummary.summarize([workout("Workout", cycling: false, rated: 4)]).verdict, .noRides)
        XCTAssertEqual(EffortCheckSummary.summarize([]).verdict, .noRides)
    }

    func testVerdict_textNamesTheCounts() {
        XCTAssertEqual(EffortCheckSummary.Verdict.someRidesRated(rated: 3, rides: 12).text,
                       "3 of your 12 rides carry an effort rating.")
        XCTAssertEqual(EffortCheckSummary.Verdict.noRatedRides.text,
                       "None of your rides carry an effort rating, or Effort access is off.")
        XCTAssertEqual(EffortCheckSummary.Verdict.noRides.text, "No rides in this period.")
        XCTAssertEqual(EffortCheckSummary.Verdict.allRidesRated(rides: 4).text, "All 4 of your rides carry an effort rating.")
    }

    func testSummary_equalCountSourcesSortByName() {
        let summary = EffortCheckSummary.summarize([workout("Zwift"), workout("Garmin"), workout("Strava")])
        XCTAssertEqual(summary.sources.map(\.name), ["Garmin", "Strava", "Zwift"])
    }

    /// Any app can write a workout effort score, so the screen names who wrote each rating:
    /// only one from Fitness or the Watch is the rider's own.
    func testSummary_countsRatingsByTheAppThatWroteThem() {
        let summary = EffortCheckSummary.summarize([
            workout("Strava", rated: 6, ratedBy: "Fitness"),
            workout("Strava", rated: 5, ratedBy: "Fitness"),
            workout("Wahoo", rated: 7, ratedBy: "Wahoo"),
            workout("Strava", estimated: 4)
        ])
        XCTAssertEqual(summary.ratingWriters, [EffortCheckSummary.Writer(name: "Fitness", ratings: 2),
                                               EffortCheckSummary.Writer(name: "Wahoo", ratings: 1)])
    }
}
