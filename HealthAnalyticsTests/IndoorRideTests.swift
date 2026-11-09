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
        XCTAssertEqual(try activity(type: "VirtualRide", sportType: "VirtualRide", polyline: "abc123").isIndoor, true,
                      "Zwift has a virtual route but is indoor")
    }

    func testIsIndoor_trainerFlagIsIndoor() throws {
        XCTAssertEqual(try activity(trainer: true, polyline: "abc123").isIndoor, true)
    }

    func testIsIndoor_noRouteIsIndoor() throws {
        XCTAssertEqual(try activity(trainer: false, polyline: "").isIndoor, true, "TrainerRoad uploads have no route")
    }

    func testIsIndoor_routeIsOutdoor() throws {
        XCTAssertEqual(try activity(trainer: false, polyline: "abc123").isIndoor, false)
    }

    /// No map data at all says nothing about the route (an API or scope change could strip it), so
    /// the setting is unknown and the ride isn't priced, rather than every ride reading indoor.
    func testDecode_missingMapIsUnknown() throws {
        XCTAssertNil(try activity(includeMap: false).isIndoor)
        XCTAssertEqual(try activity(trainer: true, includeMap: false).isIndoor, true, "The trainer flag still says indoor")
        XCTAssertEqual(try activity(type: "VirtualRide", includeMap: false).isIndoor, true)
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

    // MARK: - Fill orchestration (Craig, review D2)

    private let cutoff = ISO8601DateFormatter().date(from: "2026-07-12T00:00:00Z")!

    private func fullPage(id start: Int, date: String = "2026-10-01T12:00:00Z") throws -> [StravaActivity] {
        try (0..<SyncManager.stravaActivitiesPageSize).map { i in
            var body: [String: Any] = ["id": start + i, "name": "Ride", "type": "Ride", "start_date": date,
                                       "distance": 1.0, "moving_time": 1, "elapsed_time": 1, "total_elevation_gain": 0.0]
            body["map"] = ["summary_polyline": i % 2 == 0 ? "abc" : ""]
            return try JSONDecoder().decode(StravaActivity.self, from: JSONSerialization.data(withJSONObject: body))
        }
    }

    func testIndoorFill_failedPageLeavesItPending() async throws {
        let first = try fullPage(id: 0)
        var applied = false
        let outcome = await SyncManager.runIndoorFill(alreadyDone: false, isAuthenticated: true, cutoff: cutoff,
            fetchPage: { page in
                if page == 1 { return first }
                throw URLError(.timedOut)
            },
            apply: { _ in applied = true; return 0 })
        XCTAssertEqual(outcome, .fetchFailed)
        XCTAssertFalse(applied, "Nothing is written from a partial list")
    }

    func testIndoorFill_failedWriteLeavesItPending() async throws {
        let outcome = await SyncManager.runIndoorFill(alreadyDone: false, isAuthenticated: true, cutoff: cutoff,
            fetchPage: { _ in [try self.activity(polyline: "abc")] }, apply: { _ in nil })
        XCTAssertEqual(outcome, .writeFailed)
    }

    func testIndoorFill_appliesEveryPageAndSkipsUnknown() async throws {
        let first = try fullPage(id: 0), second = [try activity(polyline: "abc")]
        let unknown = try activity(includeMap: false)
        var written: [String: Bool] = [:]
        let outcome = await SyncManager.runIndoorFill(alreadyDone: false, isAuthenticated: true, cutoff: cutoff,
            fetchPage: { page in page == 1 ? first : second + [unknown] },
            apply: { flags in written = flags; return flags.count })
        XCTAssertEqual(outcome, .done(changed: SyncManager.stravaActivitiesPageSize),
                       "Ids 0...199 from page 1; page 2's rides reuse id 1, and its unknown one is left out")
        XCTAssertEqual(written["0"], false, "A route reads outdoor")
        XCTAssertEqual(written["1"], false, "Page 2's later answer for id 1 wins")
        XCTAssertEqual(written.count, SyncManager.stravaActivitiesPageSize)
    }

    func testIndoorFill_doneOrSignedOutFetchesNothing() async throws {
        var fetched = false
        for (done, signedIn) in [(true, true), (false, false)] {
            let outcome = await SyncManager.runIndoorFill(alreadyDone: done, isAuthenticated: signedIn, cutoff: cutoff,
                fetchPage: { _ in fetched = true; return [] }, apply: { _ in 0 })
            XCTAssertEqual(outcome, .skipped)
        }
        XCTAssertFalse(fetched)
    }
}
