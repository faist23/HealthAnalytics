//
//  IndoorRideTests.swift
//  HealthAnalyticsTests
//
//  Indoor or outdoor, from Strava (Craig: "if there is a gps route, it's an outdoor ride";
//  Zwift's virtual route is the exception). Spec: docs/superpowers/specs/2026-11-09-ride-cost-design.md
//

import XCTest
import HealthKit
import SwiftData
@testable import HealthAnalytics

final class IndoorRideTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func activity(type: String = "Ride", sportType: String? = nil, trainer: Bool? = nil,
                          polyline: String? = nil, includeMap: Bool = true) throws -> StravaActivity {
        var body: [String: Any] = [
            "id": 1, "name": "Ride", "type": type, "start_date": "2026-11-01T12:00:00Z",
            "distance": 30000.0, "moving_time": 3600, "elapsed_time": 3700, "total_elevation_gain": 100.0,
        ]
        if let sportType { body["sport_type"] = sportType }
        if let trainer { body["trainer"] = trainer }
        if includeMap { body["map"] = ["summary_polyline": polyline ?? ""] }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try JSONDecoder().decode(StravaActivity.self, from: data)
    }

    func testIsIndoor_virtualRideWithRouteIsIndoor() throws {
        XCTAssertTrue(try activity(type: "VirtualRide", sportType: "VirtualRide", polyline: "abc123").isIndoor,
                      "Zwift has a virtual route but is indoor")
    }

    func testIsIndoor_trainerFlagIsIndoor() throws {
        XCTAssertTrue(try activity(trainer: true, polyline: "abc123").isIndoor)
    }

    func testIsIndoor_noRouteIsIndoor() throws {
        XCTAssertTrue(try activity(trainer: false, polyline: "").isIndoor, "TrainerRoad uploads have no route")
    }

    func testIsIndoor_routeIsOutdoor() throws {
        XCTAssertFalse(try activity(trainer: false, polyline: "abc123").isIndoor)
    }

    func testDecode_missingNewFieldsStillDecodes() throws {
        XCTAssertTrue(try activity(includeMap: false).isIndoor, "No map at all reads as no route")
    }

    // MARK: - Stored

    private func container() throws -> ModelContainer {
        let schema = Schema([StoredWorkout.self, StoredHealthMetric.self, StoredNutrition.self,
                             StoredIntentLabel.self, StoredFTPSnapshot.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func stravaRide(id: String = "strava-1", isIndoor: Bool?) -> StravaImportData {
        StravaImportData(id: id, title: "Ride", workoutType: .cycling, startDate: start, duration: 3600,
                         distance: nil, power: 200, normalizedPower: 210, energy: nil, averageHeartRate: 140,
                         isIndoor: isIndoor)
    }

    private func upsert(_ persistence: DataPersistenceActor, _ rides: [StravaImportData]) async {
        await persistence.upsertRecentData(workouts: [], strava: rides, sleep: [], hrv: [], rhr: [],
                                           steps: [], weight: [], nutrition: [], vo2max: [])
    }

    func testUpsert_setsIndoor() async throws {
        let container = try container()
        let persistence = DataPersistenceActor(modelContainer: container)
        await upsert(persistence, [stravaRide(isIndoor: true)])
        await upsert(persistence, [stravaRide(isIndoor: false)])
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        XCTAssertEqual(stored.map(\.isIndoor), [false], "A later sync's answer replaces the stored one")
    }

    /// Review focus 1: a re-upsert that doesn't know the setting keeps it.
    func testUpsert_nilIndoorKeepsStoredValue() async throws {
        let container = try container()
        let persistence = DataPersistenceActor(modelContainer: container)
        await upsert(persistence, [stravaRide(isIndoor: true)])
        await upsert(persistence, [stravaRide(isIndoor: nil)])
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        XCTAssertEqual(stored.map(\.isIndoor), [true])
    }
}
