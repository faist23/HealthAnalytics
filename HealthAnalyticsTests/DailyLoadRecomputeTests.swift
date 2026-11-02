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
    //   fails_when=the recompute rewrites readinessScore or dailyStrain (constraint 3);
    //   why_new=TODO constraint; seam=recomputeRecentDailyLoads (non-test callers: 1); no_claim=none
    func test_recoveryAndACWR_areNeverRewritten() throws {
        let row = score(1, load: 0, count: 0, readiness: 64, strain: 1.37)
        ride("r", daysAgo: 1)
        try context.save()
        _ = recompute()
        XCTAssertEqual(row.readinessScore, 64); XCTAssertEqual(row.dailyStrain, 1.37)
    }

    // Value: protects=today, days outside the 7-day window and days with no row are left alone
    //   (no row is created); fails_when=the window or the today/no-insert guard drifts
    //   (constraints 7, today rewritten by analysis); why_new=new; seam=recomputeRecentDailyLoads
    //   (non-test callers: 1); no_claim=none beyond protects
    func test_todayOldDaysAndMissingRows_areUntouched() throws {
        let today = score(0, load: 0); let old = score(8, load: 0)
        ride("t", daysAgo: 0); ride("o", daysAgo: 8); ride("norow", daysAgo: 4)
        try context.save()
        XCTAssertEqual(recompute(), 0)
        XCTAssertEqual(today.dailyLoad, 0); XCTAssertEqual(old.dailyLoad, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredDailyScore>()).count, 2, "no row created")
    }

    // Value: protects=an unchanged day isn't rewritten (within 0.01), and a row is found by its
    //   dateString even when its date's time would put startOfDay on another day (constraint 5);
    //   fails_when=rows are matched by startOfDay(date) or written every time; why_new=TODO
    //   constraints 5–6; seam=recomputeRecentDailyLoads (non-test callers: 1); no_claim=real travel
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

    // MARK: Store trust

    // Value: protects=the recent fetch always reaches at least 7 days back (backdated uploads
    //   arrive) and still reaches past a longer gap; fails_when=the window goes back to "since
    //   last sync minus a day"; why_new=TODO constraint 2; seam=none; no_claim=HealthKit's real
    //   late writers
    func test_recentSyncWindow_coversAtLeastSevenDays() {
        let sevenBack = cal.date(byAdding: .day, value: -7, to: now)!
        XCTAssertEqual(SyncManager.recentSyncWindowStart(lastSync: now.addingTimeInterval(-3600), now: now), sevenBack)
        let longAgo = cal.date(byAdding: .day, value: -20, to: now)!
        XCTAssertEqual(SyncManager.recentSyncWindowStart(lastSync: longAgo, now: now), cal.date(byAdding: .day, value: -1, to: longAgo)!)
        XCTAssertEqual(SyncManager.recentSyncWindowStart(lastSync: nil, now: now), cal.date(byAdding: .day, value: -30, to: now)!)
    }

    // Value: protects=a HealthKit ride paired with a STORED Strava ride isn't stored again when
    //   Strava's list didn't come back this sync; fails_when=the foreground upsert dedupes only
    //   against the fetched list again (TODO constraint 1); why_new=TODO; seam=none (real actor,
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
}
