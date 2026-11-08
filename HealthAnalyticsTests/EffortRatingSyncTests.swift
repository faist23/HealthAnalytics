//
//  EffortRatingSyncTests.swift
//  HealthAnalyticsTests
//
//  Sync attaches each Apple Watch effort rating to the stored ride it overlaps.
//

import XCTest
import SwiftData
import HealthKit
@testable import HealthAnalytics

@MainActor
final class EffortRatingSyncTests: XCTestCase {

    private var ctx: ModelContext!
    private var container: ModelContainer!
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    override func setUp() async throws {
        container = try ModelContainer(for: Schema([StoredWorkout.self, StoredFTPSnapshot.self]),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        ctx = ModelContext(container)
    }

    private func at(_ daysAgo: Int, _ hour: Double) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(hour * 3600)
    }

    @discardableResult
    private func insert(_ id: String, start: Date, minutes: Double = 60, type: HKWorkoutActivityType = .cycling) -> StoredWorkout {
        let workout = StoredWorkout(id: id, type: type, startDate: start, duration: minutes * 60,
                                    distance: nil, power: nil, energy: nil, hr: nil, source: "test")
        ctx.insert(workout)
        return workout
    }

    private func rating(_ value: Double, start: Date, minutes: Double = 60) -> EffortRatingSample {
        EffortRatingSample(workoutStart: start, workoutEnd: start.addingTimeInterval(minutes * 60), rating: value)
    }

    private func apply(_ ratings: [EffortRatingSample]) throws {
        DataPersistenceActor.applyEffortRatings(ratings, windowStart: at(14, 0), in: ctx)
        try ctx.save()
    }

    private func stored(_ id: String) throws -> StoredWorkout {
        try XCTUnwrap(try ctx.fetch(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })).first)
    }

    func testApplyRatings_writesToTheOverlappingRide() throws {
        insert("strava-1", start: at(1, 9))
        try apply([rating(7, start: at(1, 9).addingTimeInterval(120), minutes: 59)])
        XCTAssertEqual(try stored("strava-1").effortRating, 7)
    }

    func testApplyRatings_oneRatingOneRide() throws {
        insert("big-overlap", start: at(1, 9))
        insert("small-overlap", start: at(1, 9.75))
        try apply([rating(6, start: at(1, 9))])
        XCTAssertEqual(try stored("big-overlap").effortRating, 6)
        XCTAssertNil(try stored("small-overlap").effortRating, "A rating goes to its single best overlap")
    }

    func testApplyRatings_needsHalfTheShorterWorkout() throws {
        insert("barely", start: at(1, 9.6))
        try apply([rating(6, start: at(1, 9))])
        XCTAssertNil(try stored("barely").effortRating, "24 of 60 minutes overlap is under half")
    }

    func testApplyRatings_updatesAndClears() throws {
        insert("ride", start: at(1, 9))
        try apply([rating(6, start: at(1, 9))])
        try apply([rating(8, start: at(1, 9))])
        XCTAssertEqual(try stored("ride").effortRating, 8)
        insert("other", start: at(2, 9))
        try apply([rating(5, start: at(2, 9))])
        XCTAssertNil(try stored("ride").effortRating, "A rating removed in Apple Health clears here too")
    }

    func testApplyRatings_leavesRidesOutsideTheWindowAlone() throws {
        let old = insert("old", start: at(20, 9))
        old.effortRating = 5
        try apply([])
        XCTAssertEqual(try stored("old").effortRating, 5)
    }

    func testApplyRatings_ignoresNonCyclingWorkouts() throws {
        insert("run", start: at(1, 9), type: .running)
        try apply([rating(6, start: at(1, 9))])
        XCTAssertNil(try stored("run").effortRating)
    }

    /// Apple Health hides a denied read as "no samples", so an empty list is unknown, not "all deleted".
    func testApplyRatings_emptyListKeepsStoredRatings() throws {
        insert("ride", start: at(1, 9))
        try apply([rating(6, start: at(1, 9))])
        try apply([])
        XCTAssertEqual(try stored("ride").effortRating, 6)
    }

    func testApplyRatings_zeroLengthSampleAssignsNothing() throws {
        insert("ride", start: at(1, 9))
        try apply([rating(6, start: at(1, 9), minutes: 0)])
        XCTAssertNil(try stored("ride").effortRating)
    }
}
