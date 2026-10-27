//
//  HealthKitWorkoutRefreshTests.swift
//  HealthAnalyticsTests
//
//  The background pass refreshes workouts from HealthKit only (no Strava). A ride the
//  foreground already stored as its Strava copy must not gain a second, HealthKit-UUID
//  row: double load fakes tapers and back-to-back crashes.
//

import XCTest
import HealthKit
@testable import HealthAnalytics

final class HealthKitWorkoutRefreshTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func healthKitRide(offset: TimeInterval = 0, minutes: Double = 60,
                               type: HKWorkoutActivityType = .cycling) -> WorkoutData {
        let s = start.addingTimeInterval(offset)
        return WorkoutData(workoutType: type, startDate: s, endDate: s.addingTimeInterval(minutes * 60),
                           duration: minutes * 60, totalEnergyBurned: nil, totalDistance: nil,
                           averagePower: nil, averageHeartRate: 140, source: .appleWatch)
    }

    private func storedStravaRide(offset: TimeInterval = 0, minutes: Double = 60) -> StravaImportData {
        StravaImportData(id: "strava-1", title: "Ride", workoutType: .cycling,
                         startDate: start.addingTimeInterval(offset), duration: minutes * 60,
                         distance: nil, power: 200, normalizedPower: 210, energy: nil, averageHeartRate: 140)
    }

    /// Review focus 1.
    func test_rideAlreadyStoredAsStrava_isNotUpsertedAgain() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide()], storedStrava: [storedStravaRide(offset: 30)])
        XCTAssertTrue(result.isEmpty)
    }

    func test_rideWithNoStravaCopy_isKept() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide()], storedStrava: [])
        XCTAssertEqual(result.count, 1)
    }

    func test_differentActivityAtTheSameTime_isKept() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide(type: .running)], storedStrava: [storedStravaRide()])
        XCTAssertEqual(result.count, 1, "A run overlapping a stored ride is a different workout")
    }

    func test_nonOverlappingRide_isKept() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide(offset: 6 * 3600)], storedStrava: [storedStravaRide()])
        XCTAssertEqual(result.count, 1)
    }
}
