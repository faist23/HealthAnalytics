//
//  FTPHistoryTests.swift
//  HealthAnalyticsTests
//
//  Tests for FTP History Management feature.
//
//  Coverage:
//    - StoredFTPSnapshot.resolved(for:snapshots:) — 6 cases
//    - StoredFTPSnapshot.upsertIfChanged — 3 cases (same-day dedup)
//    - PredictiveReadinessService.calculateWorkoutLoad — zone weights + TSS formula
//

import XCTest
import SwiftData
import HealthKit
@testable import HealthAnalytics

// MARK: - Helpers

private func snap(date: Date, watts: Int, source: String = "manual") -> StoredFTPSnapshot {
    StoredFTPSnapshot(date: date, watts: watts, source: source)
}

private func day(_ iso: String) -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")!
    return f.date(from: iso)!
}

private func makeInMemoryContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: StoredFTPSnapshot.self, configurations: config)
    return ModelContext(container)
}

// MARK: - resolved(for:snapshots:) Tests

final class StoredFTPSnapshotResolvedTests: XCTestCase {

    // Empty → fall back to 200W default
    func test_resolved_emptySnapshots_returns200W() {
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: Date(), snapshots: []),
            200.0
        )
    }

    // Single snapshot before the workout date — use it
    func test_resolved_singleSnapshotBeforeWorkout() {
        let snapshots = [snap(date: day("2025-01-01"), watts: 250)]
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-06-15"), snapshots: snapshots),
            250.0
        )
    }

    // Single snapshot strictly after the workout date — not yet effective → 200W default
    func test_resolved_singleSnapshotAfterWorkout_returnsDefault() {
        let snapshots = [snap(date: day("2025-06-01"), watts: 250)]
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-01-01"), snapshots: snapshots),
            200.0
        )
    }

    // Workout on the exact snapshot date — inclusive boundary (<=), so snapshot is used
    func test_resolved_exactBoundaryDate_included() {
        let boundary = day("2025-03-15")
        let snapshots = [snap(date: boundary, watts: 260)]
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: boundary, snapshots: snapshots),
            260.0
        )
    }

    // FTP returns to a prior value: 250 → 230 → 250.
    // Workout after the second 250W entry should use 250, not 230.
    func test_resolved_ftpReturnsToPriorValue() {
        let snapshots = [
            snap(date: day("2024-01-01"), watts: 250),
            snap(date: day("2024-06-01"), watts: 230), // injury — fitness dropped
            snap(date: day("2025-01-01"), watts: 250)  // back to form
        ]
        // Ride on 2025-02-01 should resolve to the Jan 2025 entry (250W)
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-02-01"), snapshots: snapshots),
            250.0
        )
        // Ride on 2024-08-01 should resolve to the Jun 2024 entry (230W)
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2024-08-01"), snapshots: snapshots),
            230.0
        )
        // Ride on 2024-03-01 should resolve to the Jan 2024 entry (250W)
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2024-03-01"), snapshots: snapshots),
            250.0
        )
    }

    // Workout between two snapshots — uses the earlier one (most recent ≤ date)
    func test_resolved_workoutBetweenTwoSnapshots_usesEarlier() {
        let snapshots = [
            snap(date: day("2025-01-01"), watts: 240),
            snap(date: day("2025-07-01"), watts: 260)
        ]
        // Workout in April sits between them — Jan snapshot is the most recent ≤ April
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-04-01"), snapshots: snapshots),
            240.0
        )
    }
}

// MARK: - upsertIfChanged (same-day dedup) Tests

@MainActor
final class StoredFTPSnapshotUpsertTests: XCTestCase {

    // Same day, same watts → skip (returns false, no new row)
    func test_upsertIfChanged_sameDaySameWatts_skips() throws {
        let context = try makeInMemoryContext()
        // Pre-insert a snapshot for today
        let today = Calendar.current.startOfDay(for: Date())
        context.insert(StoredFTPSnapshot(date: today, watts: 250, source: "strava_profile"))
        try context.save()

        let inserted = StoredFTPSnapshot.upsertIfChanged(watts: 250, source: "strava_profile", context: context)

        XCTAssertFalse(inserted, "Should skip when same watts already recorded today")
        let all = try context.fetch(FetchDescriptor<StoredFTPSnapshot>())
        XCTAssertEqual(all.count, 1, "No duplicate should be created")
    }

    // Same day, different watts → update in place (no duplicate row created)
    func test_upsertIfChanged_sameDayDifferentWatts_updatesInPlace() throws {
        let context = try makeInMemoryContext()
        let today = Calendar.current.startOfDay(for: Date())
        context.insert(StoredFTPSnapshot(date: today, watts: 250, source: "strava_profile"))
        try context.save()

        let updated = StoredFTPSnapshot.upsertIfChanged(watts: 260, source: "strava_profile", context: context)

        XCTAssertTrue(updated, "Should return true when watts changed on same day")
        let all = try context.fetch(FetchDescriptor<StoredFTPSnapshot>())
        XCTAssertEqual(all.count, 1, "Must update in place — no duplicate row")
        XCTAssertEqual(all.first?.watts, 260, "Watts must reflect the updated value")
    }

    // Different day, same watts → insert.
    // This is the 250→230→250 bug fix: a returning-to-prior-value entry must not be rejected.
    func test_upsertIfChanged_differentDaySameWatts_inserts() throws {
        let context = try makeInMemoryContext()
        // Yesterday had 250W
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        context.insert(StoredFTPSnapshot(date: yesterday, watts: 250, source: "strava_profile"))
        try context.save()

        // Today also resolves to 250W — must insert (different day)
        let inserted = StoredFTPSnapshot.upsertIfChanged(watts: 250, source: "strava_profile", context: context)

        XCTAssertTrue(inserted, "Should insert even when watts match a prior day's entry")
        let all = try context.fetch(FetchDescriptor<StoredFTPSnapshot>())
        XCTAssertEqual(all.count, 2)
    }
}

// MARK: - calculateWorkoutLoad Tests

final class PredictiveReadinessServiceLoadTests: XCTestCase {

    private let service = PredictiveReadinessService()

    // PATH 1: Zone-weighted load.
    // 1 hour entirely in Z5 (index 4, weight 5.5) → load = 5.5
    func test_calculateLoad_zoneWeighted_pureZ5() {
        let zoneSecs: [Double] = [0, 0, 0, 0, 3600, 0, 0]  // 1 hr Z5
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            powerZoneSeconds: zoneSecs,
            averageHeartRate: nil,
            source: .strava
        )
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [])
        XCTAssertEqual(load, 5.5, accuracy: 0.01)
    }

    // Zone weights sum: 1 hr in each of Z1–Z7 = sum of all weights = 30.5
    func test_calculateLoad_zoneWeighted_oneHourEachZone() {
        let zoneSecs = [Double](repeating: 3600.0, count: 7)
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(7 * 3600),
            duration: 7 * 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            powerZoneSeconds: zoneSecs,
            averageHeartRate: nil,
            source: .strava
        )
        let expectedLoad = PredictiveReadinessService.zoneWeights.reduce(0, +)  // 30.5
        XCTAssertEqual(
            service.calculateWorkoutLoad(workout, ftpSnapshots: []),
            expectedLoad,
            accuracy: 0.01
        )
    }

    // PATH 2: NP-based TSS. IF = NP/FTP, TSS = IF² × durationHours
    // NP=200W, FTP=200W → IF=1.0 → TSS = 1.0 × 1.0 = 1.0 per hour
    func test_calculateLoad_npTSS_thresholdEffort_oneHour() {
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            normalizedPower: 200,
            powerZoneSeconds: nil,
            averageHeartRate: nil,
            source: .strava
        )
        // FTP snapshot for today = 200W
        let snapshot = StoredFTPSnapshot(date: Calendar.current.startOfDay(for: Date()), watts: 200, source: "manual")
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [snapshot])
        // IF=1.0, TSS = 1.0² × 1.0hr = 1.0
        XCTAssertEqual(load, 1.0, accuracy: 0.001)
    }

    // NP=240W, FTP=200W → IF=1.2 → TSS = 1.44 × 1.0hr = 1.44
    func test_calculateLoad_npTSS_aboveThreshold_oneHour() {
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            normalizedPower: 240,
            powerZoneSeconds: nil,
            averageHeartRate: nil,
            source: .strava
        )
        let snapshot = StoredFTPSnapshot(date: Calendar.current.startOfDay(for: Date()), watts: 200, source: "manual")
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [snapshot])
        XCTAssertEqual(load, 1.44, accuracy: 0.001)
    }

    // PATH 1 takes priority over PATH 2 when both zone data and NP are present
    func test_calculateLoad_zonePriorityOverNP() {
        // 1 hr Z1 only (weight 0.5) — load should be 0.5
        // NP=250W with 200W FTP would give TSS = (1.25)² × 1.0 = 1.5625 — different
        let zoneSecs: [Double] = [3600, 0, 0, 0, 0, 0, 0]
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            normalizedPower: 250,
            powerZoneSeconds: zoneSecs,
            averageHeartRate: nil,
            source: .strava
        )
        let snapshot = StoredFTPSnapshot(date: Calendar.current.startOfDay(for: Date()), watts: 200, source: "manual")
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [snapshot])
        XCTAssertEqual(load, 0.5, accuracy: 0.01, "Zone path should win over NP path")
    }

    // MARK: - No-power-stream marker

    /// A Strava ride with estimated power has no watts stream, so the zone backfill marks
    /// it (`SyncManager.noPowerStreamCSV`) instead of re-fetching it after every sync. The
    /// marker must read exactly like "no zones": no zone seconds, and load from the next
    /// path down, never a zone-weighted load of zero.
    func test_noPowerStreamMarker_decodesAsNoZones_andLoadUsesTheNextPath() {
        let ride = StoredWorkout(
            id: "estimated-power", type: .cycling,
            startDate: Date(timeIntervalSince1970: 1_790_000_000),
            duration: 3600, distance: nil, power: 180, energy: nil, hr: nil, source: "Strava"
        )
        ride.powerZoneSecondsCSV = SyncManager.noPowerStreamCSV
        // FTP pinned by snapshot: with none, the NP path reads the simulator's stored FTP.
        let ftp = [StoredFTPSnapshot(date: Date(timeIntervalSince1970: 1_700_000_000), watts: 200, source: "manual")]

        XCTAssertNil(ride.powerZoneSeconds)
        let load = PredictiveReadinessService().calculateWorkoutLoad(WorkoutData(from: ride), ftpSnapshots: ftp)
        XCTAssertGreaterThan(load, 0.5, "A marked one-hour ride still carries real load")
    }

    // Value: protects=a ride whose Strava watts stream is all null (stored as seven zero zones)
    //   keeps real load; fails_when=the decoder hands zero zones to calculateWorkoutLoad's zone
    //   path, scoring the ride 0 so its day reads as rest (false sick-day window);
    //   why_new=only the "" marker was pinned; seam=none; no_claim=Strava's real stream shape
    //   (synthetic CSV; unit only)
    func test_allZeroZones_decodeAsNoZones_andLoadUsesTheNextPath() {
        let ride = StoredWorkout(
            id: "dropout", type: .cycling,
            startDate: Date(timeIntervalSince1970: 1_790_000_000),
            duration: 3600, distance: nil, power: 180, energy: nil, hr: nil, source: "Strava"
        )
        ride.powerZoneSecondsCSV = "0,0,0,0,0,0,0"
        let ftp = [StoredFTPSnapshot(date: Date(timeIntervalSince1970: 1_700_000_000), watts: 200, source: "manual")]

        XCTAssertNil(ride.powerZoneSeconds, "Zero seconds in every zone is no zone data")
        let load = PredictiveReadinessService().calculateWorkoutLoad(WorkoutData(from: ride), ftpSnapshots: ftp)
        XCTAssertGreaterThan(load, 0.5, "A one-hour ride with a power dropout still carries real load")
    }
}

// MARK: - No-power-stream marker: one retry a day after the miss

/// A Strava answer with no watts stream is retried once, a day after that answer, then
/// marked permanent. The clock is the miss, not the ride's start: a stream that isn't
/// processed yet happens when the ride reaches Strava, which can be days after the ride.
final class NoPowerStreamMarkerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // Value: protects=any ride's first no-watts answer gets one retry, a late upload included;
    //   fails_when=the first miss writes the permanent marker, or keys the retry on the ride's
    //   age again; why_new=the rule changed; seam=none; no_claim=the SwiftData fetch (singleton store)
    func test_firstMiss_writesARetryMarkerStampedWithTheMiss() {
        let csv = SyncManager.zoneCSVForNoPowerStream(current: nil, now: now)
        XCTAssertEqual(SyncManager.noPowerStreamRetryDate(csv), now)
    }

    // Value: protects=the retried ride's second miss is final, so it is never fetched again;
    //   fails_when=a retry marker is re-stamped instead, re-fetching it every day;
    //   why_new=new rule; seam=none; no_claim=the SwiftData fetch (singleton store)
    func test_missOnARetriedRide_writesThePermanentMarker() {
        let retried = SyncManager.noPowerStreamRetryMarker(at: now.addingTimeInterval(-2 * 86400))
        XCTAssertEqual(SyncManager.zoneCSVForNoPowerStream(current: retried, now: now), SyncManager.noPowerStreamCSV)
    }

    // Value: protects=the retry waits a full day after the miss; fails_when=the age check is
    //   inverted or dropped, re-fetching a fresh retry on the next sync; why_new=new rule;
    //   seam=none; no_claim=none beyond protects
    func test_retryIsDueADayAfterTheMiss() {
        let marker = SyncManager.noPowerStreamRetryMarker(at: now)
        XCTAssertFalse(SyncManager.isNoPowerStreamRetryDue(marker, now: now.addingTimeInterval(23 * 3600)))
        XCTAssertTrue(SyncManager.isNoPowerStreamRetryDue(marker, now: now.addingTimeInterval(SyncManager.noPowerStreamRetryAge)))
        XCTAssertFalse(SyncManager.isNoPowerStreamRetryDue(SyncManager.noPowerStreamCSV, now: now))
        XCTAssertFalse(SyncManager.isNoPowerStreamRetryDue(nil, now: now))
    }

    // Value: protects=the retry marker reads as "no zones" everywhere; fails_when=its format
    //   decodes as zones; why_new=new value; seam=none; no_claim=none beyond protects
    func test_retryMarker_decodesAsNoZones() {
        let ride = StoredWorkout(
            id: "fresh", type: .cycling, startDate: now, duration: 3600,
            distance: nil, power: 180, energy: nil, hr: nil, source: "Strava"
        )
        ride.powerZoneSecondsCSV = SyncManager.noPowerStreamRetryMarker(at: now)
        XCTAssertNil(ride.powerZoneSeconds)
    }
}

// MARK: - Deleted Strava activities don't stall the zone backfill

/// The backfill stops a pass after three consecutive fetch errors. An activity deleted on
/// Strava answers 404 on every pass, so three of them in a row used to stop every pass at
/// the same spot and older rides never got zones. A 404 is now final for that ride (marked
/// no power stream) and never counts toward the limit; rate limits and network errors still do.
final class ZoneBackfillDeletedActivityTests: XCTestCase {

    // Value: protects=a 404 from the streams endpoint is told apart from other failures;
    //   fails_when=every non-200 maps to fetchFailed again; why_new=new mapping; seam=none;
    //   no_claim=Strava's real response for a deleted activity (status code only)
    func test_streams404_isActivityNotFound_otherStatusesAreFetchFailed() {
        XCTAssertEqual(StravaManager.streamsError(forStatus: 404), .activityNotFound)
        for status in [401, 403, 429, 500, 503] {
            XCTAssertEqual(StravaManager.streamsError(forStatus: status), .fetchFailed, "status \(status)")
        }
    }

    // Value: protects=a 404 is marked like a missing stream (retry first, permanent on the
    //   retry) and only a 404 is; fails_when=a first 404 becomes permanent (a reconnected
    //   athlete's rides lose zones for good), or a rate limit/network error gets marked;
    //   why_new=new rule; seam=none; no_claim=the loop's error counting (ZoneBackfillLoopTests)
    func test_only404_marksTheRide_retryFirstThenPermanent() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let retry = SyncManager.noPowerStreamRetryMarker(at: now.addingTimeInterval(-2 * 86400))
        XCTAssertEqual(SyncManager.zoneCSVAfterFetchError(StravaError.activityNotFound, current: nil, now: now),
                       SyncManager.noPowerStreamRetryMarker(at: now))
        XCTAssertEqual(SyncManager.zoneCSVAfterFetchError(StravaError.activityNotFound, current: retry, now: now),
                       SyncManager.noPowerStreamCSV)
        for other: Error in [StravaError.fetchFailed, StravaError.notAuthenticated, URLError(.notConnectedToInternet)] {
            XCTAssertNil(SyncManager.zoneCSVAfterFetchError(other, current: nil, now: now))
        }
    }
}

// MARK: - Zone backfill loop (fake fetch, write and pause)

/// Drives `SyncManager.runZoneBackfill`, the loop `backfillPowerZones` runs with the real
/// Strava fetch, store write and 1 s pause, through fakes.
@MainActor
final class ZoneBackfillLoopTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private enum Answer { case zones([Double]), noStream, deleted, failed }
    private struct Boom: Error {}

    private func rows(_ count: Int, csv: String? = nil) -> [SyncManager.ZoneBackfillRow] {
        (0..<count).map { i in
            SyncManager.ZoneBackfillRow(id: "\(100 + i)", startDate: now.addingTimeInterval(-Double(i) * 86400), csv: csv, ftp: 200)
        }
    }

    /// Runs the loop with one scripted answer per row; returns what was written and the result.
    private func run(_ rows: [SyncManager.ZoneBackfillRow], _ answers: [Answer], pauses: Bool = true)
        async -> (writes: [String: String], fetchedIDs: [String], progress: [Int], result: (fetched: Int, stoppedOnErrors: Bool)) {
        var writes: [String: String] = [:]
        var fetchedIDs: [String] = []
        var progress: [Int] = []
        var script = answers
        let result = await SyncManager.runZoneBackfill(
            rows,
            fetch: { row in
                fetchedIDs.append(row.id)
                switch script.removeFirst() {
                case .zones(let z): return z
                case .noStream: return nil
                case .deleted: throw StravaError.activityNotFound
                case .failed: throw Boom()
                }
            },
            write: { row, csv in writes[row.id] = csv; return true },
            pause: { pauses },
            now: { self.now },
            onProgress: { progress.append($0) }
        )
        return (writes, fetchedIDs, progress, result)
    }

    // Value: protects=three rides deleted on Strava in a row no longer stop the pass, so older
    //   rides still get zones; fails_when=a 404 counts toward the 3-error stop again; why_new=the
    //   loop had no test; seam=runZoneBackfill (non-test callers: 1, backfillPowerZones);
    //   no_claim=Strava's real 404 (scripted fetch)
    func test_threeDeletedRidesInARow_doNotStopThePass() async {
        let out = await run(rows(4), [.deleted, .deleted, .deleted, .zones([60, 0, 0, 0, 0, 0, 0])])
        XCTAssertFalse(out.result.stoppedOnErrors)
        XCTAssertEqual(out.fetchedIDs.count, 4, "the ride after three deleted ones is still fetched")
        XCTAssertEqual(out.writes["100"], SyncManager.noPowerStreamRetryMarker(at: now), "a first 404 is retried once")
        XCTAssertEqual(out.writes["103"], "60,0,0,0,0,0,0")
        XCTAssertEqual(out.result.fetched, 4)
        // Extended by /ship coverage pass 2: the progress the FTP screen shows counts every written ride.
        XCTAssertEqual(out.progress, [1, 2, 3, 4])
    }

    // Value: protects=rate-limit/network errors still stop the pass after three in a row and
    //   write nothing; fails_when=the stop is removed or failures get written as permanent;
    //   why_new=the loop had no test; seam=runZoneBackfill (non-test callers: 1);
    //   no_claim=which real errors Strava returns (scripted)
    func test_threeFailuresInARow_stopThePass_andWriteNothing() async {
        let out = await run(rows(4), [.failed, .failed, .failed, .zones([1, 1, 1, 1, 1, 1, 1])])
        XCTAssertTrue(out.result.stoppedOnErrors)
        XCTAssertEqual(out.fetchedIDs.count, 3)
        XCTAssertTrue(out.writes.isEmpty)
        XCTAssertTrue(out.progress.isEmpty, "no progress for rides that wrote nothing")
    }

    // Value: protects=a success resets the error run, and a 404 neither counts nor resets it;
    //   fails_when=either rule flips; why_new=the loop had no test; seam=runZoneBackfill
    //   (non-test callers: 1); no_claim=none beyond protects
    func test_successResetsTheErrorRun_deletedNeitherCountsNorResets() async {
        let reset = await run(rows(5), [.failed, .failed, .zones([1, 1, 1, 1, 1, 1, 1]), .failed, .failed])
        XCTAssertFalse(reset.result.stoppedOnErrors)
        let notReset = await run(rows(4), [.failed, .failed, .deleted, .failed])
        XCTAssertTrue(notReset.result.stoppedOnErrors)
        XCTAssertEqual(notReset.writes["102"], SyncManager.noPowerStreamRetryMarker(at: now))
    }

    // Value: protects=a no-watts answer writes the retry marker on a fresh row and the
    //   permanent marker on a retry row; fails_when=the loop passes the wrong current CSV;
    //   why_new=only the pure rule was tested; seam=runZoneBackfill (non-test callers: 1);
    //   no_claim=none beyond protects
    func test_noStream_writesRetryOnFirstMiss_permanentOnTheRetry() async {
        let fresh = await run(rows(1), [.noStream])
        XCTAssertEqual(fresh.writes["100"], SyncManager.noPowerStreamRetryMarker(at: now))
        let retried = await run(rows(1, csv: SyncManager.noPowerStreamRetryMarker(at: now.addingTimeInterval(-2 * 86400))), [.noStream])
        XCTAssertEqual(retried.writes["100"], SyncManager.noPowerStreamCSV)
    }

    // Value: protects=a cancelled pause (app backgrounded) ends the pass after the current row;
    //   fails_when=the loop ignores cancellation; why_new=the loop had no test;
    //   seam=runZoneBackfill (non-test callers: 1); no_claim=real Task cancellation
    func test_cancelledPause_endsThePass() async {
        let out = await run(rows(3), [.zones([1, 1, 1, 1, 1, 1, 1]), .zones([1, 1, 1, 1, 1, 1, 1]), .zones([1, 1, 1, 1, 1, 1, 1])], pauses: false)
        XCTAssertEqual(out.fetchedIDs, ["100"])
        XCTAssertEqual(out.result.fetched, 1)
        // Extended by /ship coverage pass 2: a cancelled pass is not reported as Strava errors.
        XCTAssertFalse(out.result.stoppedOnErrors)
    }
}

// MARK: - Zone backfill row selection and write (in-memory store)

/// `backfillPowerZones` picks its rows with `SyncManager.zoneBackfillRows` and stores each
/// result with `writeZoneCSV`, both against the context it is given.
@MainActor
final class ZoneBackfillStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        let schema = Schema([StoredWorkout.self, StoredFTPSnapshot.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @discardableResult
    private func ride(_ id: String, daysAgo: Double, power: Double? = 180, csv: String? = nil, source: String = "Strava") -> StoredWorkout {
        let w = StoredWorkout(id: id, type: .cycling, startDate: now.addingTimeInterval(-daysAgo * 86400),
                              duration: 3600, distance: nil, power: power, energy: nil, hr: nil, source: source)
        w.powerZoneSecondsCSV = csv
        context.insert(w)
        return w
    }

    // Value: protects=the backfill fetches exactly the rides that need zones: unfetched Strava
    //   rides with power, plus retries a day past their miss; fails_when=either query or the due
    //   filter drifts (e.g. re-fetching "" rides every sync, or never retrying); why_new=the
    //   queries had no test; seam=zoneBackfillRows (non-test callers: 1, backfillPowerZones);
    //   no_claim=the on-device store (in-memory SwiftData)
    func test_rows_selectUnfetchedAndDueRetriesOnly() throws {
        ride("1", daysAgo: 1)                                                                     // unfetched: yes
        ride("2", daysAgo: 2, csv: "1,1,1,1,1,1,1")                                               // has zones: no
        ride("3", daysAgo: 3, csv: SyncManager.noPowerStreamCSV)                                  // permanent: no
        ride("4", daysAgo: 4, csv: SyncManager.noPowerStreamRetryMarker(at: now.addingTimeInterval(-2 * 86400))) // due: yes
        ride("5", daysAgo: 5, csv: SyncManager.noPowerStreamRetryMarker(at: now.addingTimeInterval(-3600)))      // not due: no
        ride("6", daysAgo: 6, power: nil)                                                         // no power: no
        ride("7", daysAgo: 7, source: "AppleWatch")                                               // not Strava: no
        ride("not-a-number", daysAgo: 8)                                                          // no activity id: no
        try context.save()

        let ids = SyncManager.zoneBackfillRows(context: context, now: now, defaultFTP: { 250 }).map(\.id)
        XCTAssertEqual(ids, ["1", "4"])
    }

    // Value: protects=rows come newest-first and capped, retries included in date order;
    //   fails_when=the order or cap changes (a failing old retry ahead of new rides stalls the
    //   pass); why_new=the ordering had no test; seam=zoneBackfillRows (non-test callers: 1);
    //   no_claim=none beyond protects
    func test_rows_areNewestFirstAndCapped() throws {
        ride("10", daysAgo: 10, csv: SyncManager.noPowerStreamRetryMarker(at: now.addingTimeInterval(-2 * 86400)))  // old due retry
        for d in 1...4 { ride("\(d)", daysAgo: Double(d)) }
        try context.save()

        let ids = SyncManager.zoneBackfillRows(context: context, now: now, limit: 3, defaultFTP: { 250 }).map(\.id)
        XCTAssertEqual(ids, ["1", "2", "3"])
    }

    // Value: protects=each ride is zoned at the FTP in effect on its date, else the stored
    //   default; fails_when=FTP resolution uses today's FTP or ignores snapshots; why_new=the
    //   per-ride lookup had no test; seam=zoneBackfillRows (non-test callers: 1);
    //   no_claim=StoredFTPSnapshot.resolved itself (tested above)
    func test_rows_carryTheFTPInEffectOnTheRideDate() throws {
        ride("20", daysAgo: 20)
        ride("1", daysAgo: 1)
        context.insert(StoredFTPSnapshot(date: now.addingTimeInterval(-30 * 86400), watts: 200, source: "manual"))
        context.insert(StoredFTPSnapshot(date: now.addingTimeInterval(-10 * 86400), watts: 260, source: "manual"))
        try context.save()
        let ftps = Dictionary(uniqueKeysWithValues: SyncManager.zoneBackfillRows(context: context, now: now, defaultFTP: { 999 }).map { ($0.id, $0.ftp) })
        XCTAssertEqual(ftps["20"], 200)
        XCTAssertEqual(ftps["1"], 260)

        try context.delete(model: StoredFTPSnapshot.self)
        try context.save()
        XCTAssertEqual(SyncManager.zoneBackfillRows(context: context, now: now, defaultFTP: { 999 }).first?.ftp, 999)
    }

    // Value: protects=a result is stored on its own ride with the FTP it was computed at;
    //   fails_when=the write targets the wrong row or drops zoneComputedAtFTP (FTP edits then
    //   never re-zone it); why_new=the write had no test; seam=writeZoneCSV (non-test callers: 1);
    //   no_claim=none beyond protects
    func test_write_setsCSVAndFTPOnThatRideOnly() throws {
        let target = ride("1", daysAgo: 1)
        let other = ride("2", daysAgo: 2)
        try context.save()

        let wrote = SyncManager.writeZoneCSV("5,0,0,0,0,0,0", for: SyncManager.ZoneBackfillRow(id: "1", startDate: target.startDate, csv: nil, ftp: 240), in: context, defaultFTP: { 240 })

        XCTAssertTrue(wrote)
        XCTAssertEqual(target.powerZoneSecondsCSV, "5,0,0,0,0,0,0")
        XCTAssertEqual(target.zoneComputedAtFTP, 240)
        XCTAssertNil(other.powerZoneSecondsCSV)
    }

    // Value: protects=an FTP edit during a running pass can't leave old-FTP zones stamped as
    //   current; fails_when=the write ignores an FTP change since the row was picked;
    //   why_new=pre-existing race found in the v0.1.18.0 adversarial review; seam=writeZoneCSV
    //   (non-test callers: 1); no_claim=the rerun after the pass (singleton wiring)
    func test_write_skipsWhenTheRidesFTPChangedSinceThePassPickedIt() throws {
        let target = ride("1", daysAgo: 1)
        context.insert(StoredFTPSnapshot(date: now.addingTimeInterval(-30 * 86400), watts: 280, source: "manual"))
        try context.save()
        // Picked at 250; the user has since set 280 for that date.
        let wrote = SyncManager.writeZoneCSV("5,0,0,0,0,0,0", for: SyncManager.ZoneBackfillRow(id: "1", startDate: target.startDate, csv: nil, ftp: 250), in: context, defaultFTP: { 250 })
        XCTAssertFalse(wrote)
        XCTAssertNil(target.powerZoneSecondsCSV, "left for the next pass at the new FTP")
    }

    // Value: protects=a write never overwrites a ride something else changed mid-pass (an FTP
    //   edit's invalidation, a reconnect's marker clear); fails_when=the compare-and-set is
    //   dropped; why_new=new guard; seam=writeZoneCSV (non-test callers: 1); no_claim=none
    func test_write_skipsWhenTheRideChangedSinceThePassPickedIt() throws {
        let target = ride("1", daysAgo: 1, csv: nil)
        try context.save()
        let pickedAsRetry = SyncManager.ZoneBackfillRow(id: "1", startDate: target.startDate,
                                                        csv: SyncManager.noPowerStreamRetryMarker(at: now), ftp: 250)
        XCTAssertFalse(SyncManager.writeZoneCSV(SyncManager.noPowerStreamCSV, for: pickedAsRetry, in: context, defaultFTP: { 250 }))
        XCTAssertNil(target.powerZoneSecondsCSV)
    }

    // Value: protects=reconnecting Strava (a new athlete, or re-granting access) gives every
    //   ride marked "no power data" another look; fails_when=the clear misses either marker or
    //   touches real zones; why_new=new; seam=clearNoPowerMarkers (non-test callers: 1, the
    //   OAuth callback); no_claim=the callback wiring itself
    func test_clearNoPowerMarkers_resetsBothMarkers_leavesZones() throws {
        let permanent = ride("1", daysAgo: 1, csv: SyncManager.noPowerStreamCSV)
        let retry = ride("2", daysAgo: 2, csv: SyncManager.noPowerStreamRetryMarker(at: now))
        let zoned = ride("3", daysAgo: 3, csv: "1,1,1,1,1,1,1")
        permanent.zoneComputedAtFTP = 250; retry.zoneComputedAtFTP = 250; zoned.zoneComputedAtFTP = 250
        try context.save()

        XCTAssertEqual(SyncManager.clearNoPowerMarkers(in: context), 2)

        XCTAssertNil(permanent.powerZoneSecondsCSV); XCTAssertNil(permanent.zoneComputedAtFTP)
        XCTAssertNil(retry.powerZoneSecondsCSV); XCTAssertNil(retry.zoneComputedAtFTP)
        XCTAssertEqual(zoned.powerZoneSecondsCSV, "1,1,1,1,1,1,1")
        XCTAssertEqual(zoned.zoneComputedAtFTP, 250)
    }
}

extension ZoneBackfillLoopTests {
    // Value: protects=a skipped write (the ride changed mid-pass) isn't counted as fetched or
    //   shown as progress; fails_when=the loop counts a write the store refused; why_new=writes
    //   can now be refused; seam=runZoneBackfill (non-test callers: 1); no_claim=none
    func test_refusedWrite_isNotCounted() async {
        let result = await SyncManager.runZoneBackfill(
            [SyncManager.ZoneBackfillRow(id: "1", startDate: Date(), csv: nil, ftp: 200)],
            fetch: { _ in [1, 1, 1, 1, 1, 1, 1] },
            write: { _, _ in false },
            pause: { true }
        )
        XCTAssertEqual(result.fetched, 0)
    }
}
