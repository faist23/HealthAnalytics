//
//  StravaDeletedRidesTests.swift
//  HealthAnalyticsTests
//
//  A ride deleted on Strava used to stay in the store and keep adding load. Each sync now
//  compares stored Strava rides with Strava's newest page of activities. A ride missing from
//  it is only a candidate: it is deleted when Strava answers 404 for that ride, and only for
//  the athlete whose rides the store holds, with read_all granted, on a store not mixed by an
//  account switch.
//

import XCTest
import SwiftData
import HealthKit
@testable import HealthAnalytics

@MainActor
final class StravaDeletedRidesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let readAll = "read,activity:read_all,profile:read_all"

    override func setUp() async throws {
        let schema = Schema([StoredWorkout.self, StoredIntentLabel.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86400) }

    @discardableResult
    private func stored(_ id: String, daysAgo: Double, source: String = "Strava") -> StoredWorkout {
        let w = StoredWorkout(id: id, type: .cycling, startDate: day(daysAgo), duration: 3600,
                              distance: nil, power: 180, energy: nil, hr: nil, source: source)
        context.insert(w)
        return w
    }

    private func candidates(listed: Set<String>, oldestDaysAgo: Double?, full: Bool) -> [String] {
        check(listed: listed, oldestDaysAgo: oldestDaysAgo, full: full).ids.sorted()
    }

    private func check(listed: Set<String>, oldestDaysAgo: Double?, full: Bool) -> DataPersistenceActor.StravaDeletionCheck {
        DataPersistenceActor.stravaDeletionCandidates(
            listedIDs: listed, oldestListed: oldestDaysAgo.map(day), pageWasFull: full, in: context
        )
    }

    private func storedIDs() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<StoredWorkout>()).map(\.id))
    }

    // MARK: Candidates

    // Value: protects=a stored Strava ride inside a full page's span that the page doesn't list
    //   is a candidate; fails_when=the candidate rule is dropped; why_new=nothing ever removed a
    //   Strava ride; seam=stravaDeletionCandidates (non-test callers: 1, the foreground sync);
    //   no_claim=Strava's real list (synthetic ids)
    func test_unlistedRideInsideAFullPagesSpan_isACandidate() throws {
        stored("1", daysAgo: 1); stored("2", daysAgo: 2); stored("3", daysAgo: 3)
        try context.save()
        XCTAssertEqual(candidates(listed: ["1", "3"], oldestDaysAgo: 3, full: true), ["2"])
    }

    // Value: protects=rides at or before a full page's oldest activity are never candidates (the
    //   page says nothing about them); fails_when=the span check is dropped; why_new=new rule;
    //   seam=stravaDeletionCandidates (non-test callers: 1); no_claim=none beyond protects
    func test_ridesAtOrBeforeAFullPagesOldestDate_areNotCandidates() throws {
        stored("1", daysAgo: 1); stored("old", daysAgo: 30); stored("tie", daysAgo: 5)
        try context.save()
        XCTAssertEqual(candidates(listed: ["1", "x"], oldestDaysAgo: 5, full: true), [])
    }

    // Value: protects=a partial page is the whole history, and HealthKit rides are never
    //   candidates; fails_when=a partial page is treated as a span, or non-Strava rows are
    //   considered; why_new=new rule; seam=stravaDeletionCandidates (non-test callers: 1);
    //   no_claim=none beyond protects
    func test_partialPageIsTheWholeHistory_andHealthKitRidesAreNeverCandidates() throws {
        stored("1", daysAgo: 1); stored("gone", daysAgo: 400); stored("hk-uuid", daysAgo: 2, source: "AppleWatch")
        try context.save()
        XCTAssertEqual(candidates(listed: ["1"], oldestDaysAgo: 1, full: false), ["gone"])
    }

    // Value: protects=an empty list, or a page with no parsed date, yields no candidates;
    //   fails_when=either guard is removed and a glitch wipes the store; why_new=new guards;
    //   seam=stravaDeletionCandidates (non-test callers: 1); no_claim=none beyond protects
    func test_emptyListOrNoParsedDate_yieldsNothing() throws {
        stored("1", daysAgo: 1)
        try context.save()
        XCTAssertEqual(candidates(listed: [], oldestDaysAgo: nil, full: false), [])
        XCTAssertEqual(candidates(listed: ["x"], oldestDaysAgo: nil, full: true), [])
    }

    // Value: protects=when none of the stored rides in the span are on the list (another account,
    //   bad data) nothing is a candidate; fails_when=the overlap guard is removed and a wrong
    //   account's list marks every stored ride; why_new=review finding (account switch);
    //   seam=stravaDeletionCandidates (non-test callers: 1); no_claim=none beyond protects
    func test_zeroOverlapWithTheList_yieldsNothing() throws {
        stored("a1", daysAgo: 1); stored("a2", daysAgo: 2)
        try context.save()
        XCTAssertEqual(candidates(listed: ["b1", "b2"], oldestDaysAgo: 3, full: true), [])
        XCTAssertTrue(check(listed: ["b1", "b2"], oldestDaysAgo: 3, full: true).refused, "refused, so it can't verify a binding")
        XCTAssertFalse(check(listed: ["a1", "a2"], oldestDaysAgo: 3, full: true).refused)
    }

    // Value: protects=more candidates than the cap is treated as bad data, not deletions;
    //   fails_when=the cap is removed (a short page mid-history would flag years of rides);
    //   why_new=review finding (short page); seam=stravaDeletionCandidates (non-test callers: 1);
    //   no_claim=none beyond protects
    func test_moreCandidatesThanTheCap_yieldsNothing() throws {
        stored("kept", daysAgo: 0.5)
        for d in 1...(DataPersistenceActor.maxStravaDeletionCandidates + 1) { stored("m\(d)", daysAgo: Double(d)) }
        try context.save()
        XCTAssertEqual(candidates(listed: ["kept"], oldestDaysAgo: 0.5, full: false), [])
        XCTAssertTrue(check(listed: ["kept"], oldestDaysAgo: 0.5, full: false).refused)
    }

    // MARK: Confirm and remove

    // Value: protects=only a ride Strava answers 404 for is deleted; a ride it still has (edited
    //   start date, private ride) or can't answer for is kept; fails_when=a non-404 answer is
    //   taken as deleted; why_new=review findings (edited dates, private rides);
    //   seam=confirmDeletedOnStrava (non-test callers: 1); no_claim=Strava's real responses (scripted)
    func test_onlyA404ConfirmsADeletion() async {
        let answers: [String: StravaManager.ActivityStatus] = ["gone": .gone, "edited": .exists, "flaky": .unknown]
        let gone = await SyncManager.confirmDeletedOnStrava(["gone", "edited", "flaky"]) { answers[$0]! }
        XCTAssertEqual(gone, ["gone"])
        XCTAssertEqual(StravaManager.activityStatus(forHTTPStatus: 404), .gone)
        XCTAssertEqual(StravaManager.activityStatus(forHTTPStatus: 200), .exists)
        for status in [401, 403, 429, 500] { XCTAssertEqual(StravaManager.activityStatus(forHTTPStatus: status), .unknown) }
    }

    // Value: protects=a confirmed ride and its intent label are removed, nothing else; fails_when=
    //   labels are left pointing at deleted workouts, or a HealthKit row is deleted by id;
    //   why_new=new; seam=removeStravaRides (non-test callers: 1); no_claim=none beyond protects
    func test_removeStravaRides_removesThoseRidesAndTheirLabelsOnly() throws {
        stored("1", daysAgo: 1); stored("2", daysAgo: 2); stored("hk", daysAgo: 3, source: "AppleWatch")
        context.insert(StoredIntentLabel(workoutId: "2", intent: .long, confidence: 0.9, source: .heuristic))
        context.insert(StoredIntentLabel(workoutId: "1", intent: .long, confidence: 0.9, source: .heuristic))
        try context.save()
        DataPersistenceActor.removeStravaRides(ids: ["2", "hk"], in: context)
        XCTAssertEqual(try storedIDs(), ["1", "hk"])
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<StoredIntentLabel>()).map(\.workoutId)), ["1"])
    }

    // MARK: Who the store belongs to

    // Value: protects=deletion runs only for the store's athlete, with read_all granted, on a
    //   store not mixed by a switch; fails_when=any of the four conditions is dropped (another
    //   account's or a private-less list deletes rides); why_new=review findings;
    //   seam=none; no_claim=the persistence of the values (UserDefaults)
    func test_deletionGate() {
        XCTAssertTrue(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, baseline: 7, mixed: false, grantedScope: readAll))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 8, baseline: 7, mixed: false, grantedScope: readAll))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, baseline: 7, mixed: true, grantedScope: readAll))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, baseline: 7, mixed: false, grantedScope: "read,activity:read"))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, baseline: 7, mixed: false, grantedScope: nil))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: nil, baseline: 7, mixed: false, grantedScope: readAll))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, baseline: nil, mixed: false, grantedScope: readAll))
    }

    // Value: protects=an unbound store binds only on a sync where the page lists every stored ride
    //   in its span (so a store already holding another account's rides never binds); fails_when=
    //   binding goes back to "whoever is connected"; why_new=review finding (pre-upgrade switch);
    //   seam=none; no_claim=none beyond protects
    func test_bindingNeedsAVerifiedPage() {
        XCTAssertEqual(SyncManager.rideStoreAthleteToBind(baseline: nil, connected: 7, grantedScope: readAll, candidateCount: 0, verified: true), 7)
        XCTAssertNil(SyncManager.rideStoreAthleteToBind(baseline: nil, connected: 7, grantedScope: readAll, candidateCount: 1, verified: true))
        XCTAssertNil(SyncManager.rideStoreAthleteToBind(baseline: nil, connected: 7, grantedScope: readAll, candidateCount: 0, verified: false))
        XCTAssertNil(SyncManager.rideStoreAthleteToBind(baseline: 5, connected: 7, grantedScope: readAll, candidateCount: 0, verified: true))
        XCTAssertNil(SyncManager.rideStoreAthleteToBind(baseline: nil, connected: 7, grantedScope: "read", candidateCount: 0, verified: true))
    }

    // Value: protects=connecting a different athlete while the store is bound marks it mixed, and
    //   it stays mixed through a switch back (A→B→A no longer deletes B's rides); fails_when=the
    //   mixed flag is dropped or cleared by reconnecting the original athlete; why_new=review
    //   finding (A→B→A); seam=none; no_claim=resetAllData clearing it (singleton)
    func test_connectingAnotherAthlete_marksTheStoreMixed_untilReset() {
        XCTAssertTrue(SyncManager.rideStoreIsMixed(afterConnecting: 8, baseline: 7, wasMixed: false))
        XCTAssertTrue(SyncManager.rideStoreIsMixed(afterConnecting: 7, baseline: 7, wasMixed: true), "switching back stays mixed")
        XCTAssertFalse(SyncManager.rideStoreIsMixed(afterConnecting: 7, baseline: 7, wasMixed: false))
        XCTAssertFalse(SyncManager.rideStoreIsMixed(afterConnecting: 7, baseline: nil, wasMixed: false))
    }
}
