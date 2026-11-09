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
                          polyline: String? = nil, includeMap: Bool = true,
                          startDate: String = "2026-11-01T12:00:00Z") throws -> StravaActivity {
        var body: [String: Any] = [
            "id": 1, "name": "Ride", "type": type, "start_date": startDate,
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

    // MARK: - One-time fill

    func testApplyIndoorFlags_setsOnlyChangedRows() async throws {
        let container = try container()
        let persistence = DataPersistenceActor(modelContainer: container)
        await upsert(persistence, [stravaRide(id: "a", isIndoor: nil), stravaRide(id: "b", isIndoor: true),
                                   stravaRide(id: "c", isIndoor: nil)])
        let changed = await persistence.applyIndoorFlags(["a": true, "b": true, "missing": false])
        XCTAssertEqual(changed, 1, "b already says indoor; missing isn't stored")
        let byId = Dictionary(uniqueKeysWithValues: try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
            .map { ($0.id, $0.isIndoor) })
        XCTAssertEqual(byId["a"], .some(true))
        XCTAssertEqual(byId["b"], .some(true))
        XCTAssertEqual(byId["c"], .some(nil), "A ride the list didn't return stays unknown")
    }

    private func page(count: Int, oldest: String) throws -> [StravaActivity] {
        try (0..<count).map { i in try activity(startDate: i == count - 1 ? oldest : "2026-11-05T12:00:00Z") }
    }

    func testIndoorFill_stopsAtCutoff() throws {
        let cutoff = ISO8601DateFormatter().date(from: "2026-07-12T00:00:00Z")!
        let full = SyncManager.stravaActivitiesPageSize
        XCTAssertTrue(SyncManager.indoorFillNeedsAnotherPage(page: try page(count: full, oldest: "2026-08-01T12:00:00Z"),
                                                             cutoff: cutoff), "A full page still inside the window")
        XCTAssertFalse(SyncManager.indoorFillNeedsAnotherPage(page: try page(count: full, oldest: "2026-07-01T12:00:00Z"),
                                                              cutoff: cutoff), "The page reached past the cutoff")
    }

    func testIndoorFill_shortPageStops() throws {
        let cutoff = ISO8601DateFormatter().date(from: "2026-07-12T00:00:00Z")!
        XCTAssertFalse(SyncManager.indoorFillNeedsAnotherPage(page: try page(count: 5, oldest: "2026-10-01T12:00:00Z"),
                                                              cutoff: cutoff), "A short page is the end of the list")
        XCTAssertFalse(SyncManager.indoorFillNeedsAnotherPage(page: [], cutoff: cutoff))
    }
}
