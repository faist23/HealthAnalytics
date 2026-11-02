//
//  DailyLoadRecomputeTests.swift
//  HealthAnalyticsTests
//
//  A day's StoredDailyScore.dailyLoad was frozen at its last write (often mid-day), so a ride
//  synced after that day's last analysis (an evening ride synced next morning, a backdated
//  Garmin/Zwift upload) never counted, and a deleted ride kept its load. After each foreground
//  sync the last 7 complete days' existing rows are recomputed from the stored workouts. The
//  store is made trustworthy first: a failed sync doesn't move lastSyncDate, the fetch covers
//  at least 7 days, and a HealthKit ride paired with a stored Strava ride isn't stored twice.
//

import XCTest
import SwiftData
import HealthKit
@testable import HealthAnalytics

@MainActor
final class DailyLoadRecomputeTests: XCTestCase {
    // A fixed local noon, so day boundaries don't depend on when the suite runs.
    private let now: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 20; c.hour = 12
        return Calendar.current.date(from: c)!
    }()
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let cal = Calendar.current
    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    override func setUp() async throws {
        let schema = Schema([CachedAnalysis.self, StoredWorkout.self, StoredHealthMetric.self, StoredNutrition.self,
                             StoredIntentLabel.self, TrainingPattern.self, StoredDailyScore.self,
                             StoredFTPSnapshot.self, CoachMemoryNote.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func dayStart(_ daysAgo: Int) -> Date { cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now))! }

    @discardableResult
    private func score(_ daysAgo: Int, load: Double, count: Int = 0, readiness: Int = 70, strain: Double = 1.1) -> StoredDailyScore {
        let s = StoredDailyScore(date: dayStart(daysAgo).addingTimeInterval(9 * 3600), readinessScore: readiness,
                                 dailyStrain: strain, workoutCount: count, dailyLoad: load)
        context.insert(s)
        return s
    }

    @discardableResult
    private func ride(_ id: String, daysAgo: Int, hour: Double = 18, source: String = "Strava") -> StoredWorkout {
        let w = StoredWorkout(id: id, type: .cycling, startDate: dayStart(daysAgo).addingTimeInterval(hour * 3600),
                              duration: 3600, distance: nil, power: nil, energy: nil, hr: 140, source: source)
        context.insert(w)
        return w
    }

    /// One unit of load per ride, so the arithmetic in the assertions is obvious.
    private func recompute() -> Int {
        ReadinessRepository.recomputeRecentDailyLoads(context: context, now: now) { _ in 1.0 }
    }

    // MARK: Recompute

    // Value: protects=a ride stored after its day's row was written now counts in that day's
    //   load and count; fails_when=past rows stay frozen again; why_new=P2 TODO; seam=
    //   recomputeRecentDailyLoads (non-test callers: 1, the DataSyncCompleted handler);
    //   no_claim=the real load formula (load closure injected; calculateWorkoutLoad has its own tests)
    func test_aLateRide_isAddedToItsDaysLoadAndCount() throws {
        let row = score(2, load: 1, count: 1)
        ride("morning", daysAgo: 2, hour: 7); ride("evening", daysAgo: 2, hour: 19)
        try context.save()
        XCTAssertEqual(recompute(), 1)
        XCTAssertEqual(row.dailyLoad, 2); XCTAssertEqual(row.workoutCount, 2)
    }

    // Value: protects=a ride removed from the store (deleted on Strava) drops out of its day;
    //   fails_when=the recompute only ever adds; why_new=v0.1.19.0 removes rides; seam=
    //   recomputeRecentDailyLoads (non-test callers: 1); no_claim=none beyond protects
    func test_aRemovedRide_leavesItsDaysLoad() throws {
        let row = score(3, load: 2, count: 2)
        ride("kept", daysAgo: 3)
        try context.save()
        XCTAssertEqual(recompute(), 1)
        XCTAssertEqual(row.dailyLoad, 1); XCTAssertEqual(row.workoutCount, 1)
    }

    // Value: protects=only load and count change; recovery score and ACWR stay as written;
    //   fails_when=the recompute rewrites readinessScore or dailyStrain (the P2 rule: load and count only);
    //   why_new=P2 TODO; seam=recomputeRecentDailyLoads (non-test callers: 1); no_claim=none
    func test_recoveryAndACWR_areNeverRewritten() throws {
        let row = score(1, load: 0, count: 0, readiness: 64, strain: 1.37)
        ride("r", daysAgo: 1)
        try context.save()
        _ = recompute()
        XCTAssertEqual(row.readinessScore, 64); XCTAssertEqual(row.dailyStrain, 1.37)
    }

    // Value: protects=today, days outside the 7-day window and days with no row are left alone
    //   (no row is created), and day 7 is still in; fails_when=the window grows or shrinks, or the
    //   today/no-insert guard drifts (missing rows are never filled; analysis rewrites today);
    //   why_new=new; seam=recomputeRecentDailyLoads
    //   (non-test callers: 1); no_claim=none beyond protects
    func test_todayOldDaysAndMissingRows_areUntouched() throws {
        let today = score(0, load: 0); let old = score(8, load: 0); let edge = score(7, load: 0)
        ride("t", daysAgo: 0); ride("o", daysAgo: 8); ride("norow", daysAgo: 4); ride("e", daysAgo: 7)
        try context.save()
        XCTAssertEqual(recompute(), 1, "only day 7")
        XCTAssertEqual(today.dailyLoad, 0); XCTAssertEqual(old.dailyLoad, 0); XCTAssertEqual(edge.dailyLoad, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredDailyScore>()).count, 3, "no row created")
    }

    // Value: protects=an unchanged day isn't rewritten (within 0.01), and a row is found by its
    //   dateString even when its date's time would put startOfDay on another day (a stored date drifts
    //   across midnight when travelling);
    //   fails_when=rows are matched by startOfDay(date) or written every time; why_new=P2 TODO
    //   (key by dateString, write only on change); seam=recomputeRecentDailyLoads (non-test callers: 1); no_claim=real travel
    func test_unchangedDaysAreNotWritten_andRowsAreKeyedByDateString() throws {
        let same = score(2, load: 1.005, count: 1)
        ride("s", daysAgo: 2)
        // A row whose stored date drifted (written while travelling) but whose dateString is day 5.
        let drifted = StoredDailyScore(date: dayStart(4).addingTimeInterval(2 * 3600), readinessScore: 70,
                                       dailyStrain: 1, workoutCount: 0, dailyLoad: 0)
        drifted.dateString = formatter.string(from: dayStart(5))
        context.insert(drifted)
        ride("d", daysAgo: 5)
        try context.save()
        XCTAssertEqual(recompute(), 1, "only the drifted row moved")
        XCTAssertEqual(same.dailyLoad, 1.005)
        XCTAssertEqual(drifted.dailyLoad, 1)
    }

    // Value: protects=every row for a day is recomputed, so a duplicate row can't keep a removed
    //   ride's load (detectors read the day's highest row); fails_when=only the first row per
    //   dateString is written; why_new=red-team review; seam=recomputeRecentDailyLoads (non-test
    //   callers: 1); no_claim=why duplicate rows exist
    func test_duplicateRowsForADay_areAllRecomputed() throws {
        let a = score(2, load: 2, count: 2); let b = score(2, load: 2, count: 2)
        ride("kept", daysAgo: 2)
        try context.save()
        XCTAssertEqual(recompute(), 2)
        XCTAssertEqual(a.dailyLoad, 1); XCTAssertEqual(b.dailyLoad, 1)
    }

    // MARK: Store trust

    // Value: protects=the recent fetch always reaches at least 7 days back (backdated uploads
    //   arrive) and still reaches past a longer gap; fails_when=the window goes back to "since
    //   last sync minus a day"; why_new=P2 TODO (backdated uploads); seam=none; no_claim=HealthKit's real
    //   late writers
    func test_recentSyncWindow_coversAtLeastSevenDays() {
        // The start of day 7, the oldest day the recompute rewrites, not now minus 7 days.
        let sevenBack = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        XCTAssertEqual(SyncManager.recentSyncWindowStart(lastSync: now.addingTimeInterval(-3600), now: now), sevenBack)
        let longAgo = cal.date(byAdding: .day, value: -20, to: now)!
        XCTAssertEqual(SyncManager.recentSyncWindowStart(lastSync: longAgo, now: now), cal.date(byAdding: .day, value: -1, to: longAgo)!)
        XCTAssertEqual(SyncManager.recentSyncWindowStart(lastSync: nil, now: now), cal.date(byAdding: .day, value: -30, to: now)!)
    }

    // Value: protects=a HealthKit ride paired with a STORED Strava ride isn't stored again when
    //   Strava's list didn't come back this sync; fails_when=the foreground upsert dedupes only
    //   against the fetched list again; why_new=P2 TODO (no double-counted twins); seam=none (real actor,
    //   in-memory store); no_claim=WorkoutMatcher's pairing rules (tested elsewhere)
    func test_foregroundUpsert_skipsAHealthKitRidePairedWithAStoredStravaRide() async throws {
        let stored = StoredWorkout(id: "strava-1", type: .cycling, startDate: dayStart(1).addingTimeInterval(18 * 3600),
                                   duration: 3600, distance: nil, power: 200, energy: nil, hr: 140, source: "Strava")
        context.insert(stored)
        try context.save()
        let hk = WorkoutData(workoutType: .cycling, startDate: stored.startDate.addingTimeInterval(60),
                             endDate: stored.startDate.addingTimeInterval(3660), duration: 3600,
                             totalEnergyBurned: nil, totalDistance: nil, averagePower: nil,
                             averageHeartRate: 140, source: .appleWatch)
        let actor = DataPersistenceActor(modelContainer: container)
        await actor.upsertRecentData(workouts: [hk], strava: [], sleep: [], hrv: [], rhr: [], steps: [],
                                     weight: [], nutrition: [], vo2max: [])
        let ids = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>()).map(\.id)
        XCTAssertEqual(ids, ["strava-1"])
    }

    private func healthKitRide(at start: Date) -> WorkoutData {
        WorkoutData(workoutType: .cycling, startDate: start, endDate: start.addingTimeInterval(3600), duration: 3600,
                    totalEnergyBurned: nil, totalDistance: nil, averagePower: nil,
                    averageHeartRate: 140, source: .appleWatch)
    }

    // Value: protects=a HealthKit copy an earlier sync stored beside a stored Strava ride is
    //   deleted with its intent label, so the recompute doesn't count the ride twice and no
    //   label is orphaned; fails_when=the stored-Strava branch only skips, or leaves the label; why_new=testing + red-team review; seam=none (real actor, in-memory
    //   store); no_claim=how the twin got stored
    func test_foregroundUpsert_deletesAStoredHealthKitTwinOfAStoredStravaRide() async throws {
        let start = dayStart(1).addingTimeInterval(18 * 3600)
        context.insert(StoredWorkout(id: "strava-1", type: .cycling, startDate: start, duration: 3600, distance: nil,
                                     power: 200, energy: nil, hr: 140, source: "Strava"))
        let hk = healthKitRide(at: start.addingTimeInterval(60))
        context.insert(StoredWorkout(id: hk.id.uuidString, type: .cycling, startDate: hk.startDate, duration: 3600,
                                     distance: nil, power: nil, energy: nil, hr: 140, source: "Apple Watch"))
        // The background refresh labels HealthKit-UUID rows; the label must leave with the row.
        context.insert(StoredIntentLabel(workoutId: hk.id.uuidString, intent: .easy, confidence: 0.8, source: .heuristic))
        context.insert(StoredIntentLabel(workoutId: "strava-1", intent: .easy, confidence: 0.8, source: .heuristic))
        try context.save()
        let actor = DataPersistenceActor(modelContainer: container)
        await actor.upsertRecentData(workouts: [hk], strava: [], sleep: [], hrv: [], rhr: [], steps: [],
                                     weight: [], nutrition: [], vo2max: [])
        let after = ModelContext(container)
        XCTAssertEqual(try after.fetch(FetchDescriptor<StoredWorkout>()).map(\.id), ["strava-1"])
        XCTAssertEqual(try after.fetch(FetchDescriptor<StoredIntentLabel>()).map(\.workoutId), ["strava-1"],
                       "the deleted copy's label goes with it; the Strava ride's stays")
    }

    // Value: protects=a HealthKit ride that pairs with no stored Strava ride is still stored
    //   when stored Strava rides exist (the dedupe doesn't over-skip); fails_when=any stored
    //   Strava ride suppresses every HealthKit ride; why_new=coverage audit; seam=none;
    //   no_claim=WorkoutMatcher's thresholds
    func test_foregroundUpsert_storesAnUnpairedHealthKitRide() async throws {
        context.insert(StoredWorkout(id: "strava-1", type: .cycling, startDate: dayStart(1).addingTimeInterval(7 * 3600),
                                     duration: 3600, distance: nil, power: 200, energy: nil, hr: 140, source: "Strava"))
        try context.save()
        let hk = healthKitRide(at: dayStart(1).addingTimeInterval(18 * 3600))
        let actor = DataPersistenceActor(modelContainer: container)
        await actor.upsertRecentData(workouts: [hk], strava: [], sleep: [], hrv: [], rhr: [], steps: [],
                                     weight: [], nutrition: [], vo2max: [])
        let ids = Set(try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>()).map(\.id))
        XCTAssertEqual(ids, ["strava-1", hk.id.uuidString])
    }

    // Value: protects=a day whose ride count changed but whose load didn't (a 0-load ride added)
    //   is still rewritten; fails_when=the write check looks at load only; why_new=coverage
    //   audit; seam=recomputeRecentDailyLoads (non-test callers: 1); no_claim=none
    func test_aCountOnlyChange_isWritten() throws {
        let row = score(2, load: 1, count: 1)
        ride("a", daysAgo: 2); ride("b", daysAgo: 2, hour: 20)
        try context.save()
        let changed = ReadinessRepository.recomputeRecentDailyLoads(context: context, now: now) { $0.id == "a" ? 1.0 : 0.0 }
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(row.dailyLoad, 1); XCTAssertEqual(row.workoutCount, 2)
    }

    // Value: protects=an intent label the user set by hand on a Watch ride moves to its Strava
    //   ride when the Strava copy replaces it, while an automatic label is deleted (re-derived);
    //   fails_when=manual labels are deleted with the HealthKit copy, or automatic ones are
    //   carried over; why_new=v0.1.22.0 adversarial follow-up (P3 TODO); seam=none (real actor,
    //   in-memory store, both predicates translated); no_claim=the classifier relabelling
    func test_foregroundUpsert_movesAManualLabelToTheStravaRide() async throws {
        let start = dayStart(1).addingTimeInterval(18 * 3600)
        let hk = healthKitRide(at: start.addingTimeInterval(60))
        context.insert(StoredWorkout(id: hk.id.uuidString, type: .cycling, startDate: hk.startDate, duration: 3600,
                                     distance: nil, power: nil, energy: nil, hr: 140, source: "Apple Watch"))
        context.insert(StoredIntentLabel(workoutId: hk.id.uuidString, intent: .race, confidence: 1, source: .manual))
        let otherHK = healthKitRide(at: dayStart(2).addingTimeInterval(18 * 3600))
        context.insert(StoredWorkout(id: otherHK.id.uuidString, type: .cycling, startDate: otherHK.startDate, duration: 3600,
                                     distance: nil, power: nil, energy: nil, hr: 140, source: "Apple Watch"))
        context.insert(StoredIntentLabel(workoutId: otherHK.id.uuidString, intent: .easy, confidence: 0.6, source: .heuristic))
        try context.save()
        let strava = [
            StravaImportData(id: "strava-7", title: "Ride", workoutType: .cycling, startDate: start, duration: 3600,
                             distance: nil, power: 200, normalizedPower: nil, energy: nil, averageHeartRate: 140),
            StravaImportData(id: "strava-8", title: "Ride", workoutType: .cycling, startDate: otherHK.startDate,
                             duration: 3600, distance: nil, power: 180, normalizedPower: nil, energy: nil, averageHeartRate: 140)
        ]
        let actor = DataPersistenceActor(modelContainer: container)
        await actor.upsertRecentData(workouts: [hk, otherHK], strava: strava, sleep: [], hrv: [], rhr: [], steps: [],
                                     weight: [], nutrition: [], vo2max: [])
        let labels = try ModelContext(container).fetch(FetchDescriptor<StoredIntentLabel>())
        let byID = Dictionary(labels.map { ($0.workoutId, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byID["strava-7"]?.source, .manual, "the user's label moved to the Strava ride")
        XCTAssertEqual(byID["strava-7"]?.intentRawValue, ActivityIntent.race.rawValue)
        XCTAssertNil(byID[hk.id.uuidString]); XCTAssertNil(byID[otherHK.id.uuidString])
        XCTAssertNotEqual(byID["strava-8"]?.source, .manual, "an automatic label is re-derived, not carried over")
    }
}

