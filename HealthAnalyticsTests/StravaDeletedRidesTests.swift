//
//  StravaDeletedRidesTests.swift
//  HealthAnalyticsTests
//
//  A ride deleted on Strava used to stay in the store and keep adding load. Each sync now
//  compares stored Strava rides with Strava's newest page of activities. A ride missing from
//  it is only a candidate: it is deleted when Strava answers 404 for that ride, only if it is
//  tagged with the connected athlete (set when that athlete's own list returned it), and only
//  with read_all granted.
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
    private func stored(_ id: String, daysAgo: Double, source: String = "Strava", athlete: Int? = 7) -> StoredWorkout {
        let w = StoredWorkout(id: id, type: .cycling, startDate: day(daysAgo), duration: 3600,
                              distance: nil, power: 180, energy: nil, hr: nil, source: source)
        w.stravaAthleteId = source == "Strava" ? athlete : nil
        context.insert(w)
        return w
    }

    private func candidates(listed: Set<String>, oldestDaysAgo: Double?, full: Bool) -> [String] {
        check(listed: listed, oldestDaysAgo: oldestDaysAgo, full: full).ids.sorted()
    }

    private func check(listed: Set<String>, oldestDaysAgo: Double?, full: Bool, athlete: Int = 7) -> DataPersistenceActor.StravaDeletionCheck {
        DataPersistenceActor.stravaDeletionCandidates(
            athlete: athlete, listedIDs: listed, oldestListed: oldestDaysAgo.map(day), pageWasFull: full, in: context
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

    // Value: protects=exactly the cap is still trusted; fails_when=`>` becomes `>=`;
    //   why_new=review finding (one-sided boundary); seam=stravaDeletionCandidates (non-test
    //   callers: 1); no_claim=none beyond protects
    func test_exactlyTheCap_isStillTrusted() throws {
        stored("kept", daysAgo: 0.5)
        for d in 1...DataPersistenceActor.maxStravaDeletionCandidates { stored("m\(d)", daysAgo: Double(d)) }
        try context.save()
        let c = check(listed: ["kept"], oldestDaysAgo: 0.5, full: false)
        XCTAssertFalse(c.refused)
        XCTAssertEqual(c.ids.count, DataPersistenceActor.maxStravaDeletionCandidates)
    }

    // MARK: Confirm and remove

    // Value: protects=only a ride Strava answers 404 for is deleted; a ride it still has (edited
    //   start date, private ride) or can't answer for is kept; fails_when=a non-404 answer is
    //   taken as deleted; why_new=review findings (edited dates, private rides);
    //   seam=confirmDeletedOnStrava (non-test callers: 1); no_claim=Strava's real responses (scripted)
    func test_onlyA404ConfirmsADeletion() async {
        let answers: [String: StravaManager.ActivityStatus] = ["gone": .gone, "edited": .exists, "flaky": .unknown]
        let gone = await SyncManager.confirmDeletedOnStrava(["gone", "edited", "flaky"], stillSameConnection: { true }) { answers[$0]! }
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

    // MARK: Whose rides they are

    // Value: protects=only rides tagged with the connected athlete can be deleted; another
    //   account's rides, and rides never seen on a list (untagged, e.g. from before this release),
    //   are never candidates; fails_when=the tag filter is dropped (a switched account's list
    //   marks the other account's rides); why_new=review findings (account switches);
    //   seam=stravaDeletionCandidates (non-test callers: 1); no_claim=none beyond protects
    func test_onlyTheConnectedAthletesTaggedRides_areCandidates() throws {
        stored("mine-listed", daysAgo: 1); stored("mine-gone", daysAgo: 2)
        stored("other", daysAgo: 2, athlete: 8); stored("untagged", daysAgo: 3, athlete: nil)
        try context.save()
        XCTAssertEqual(candidates(listed: ["mine-listed"], oldestDaysAgo: 4, full: true), ["mine-gone"])
    }

    // Value: protects=a ride the connected athlete's own list returns is tagged with that athlete
    //   (the only way a ride becomes deletable), and a HealthKit row with a listed id isn't;
    //   fails_when=tagging stops or tags non-Strava rows; why_new=new; seam=tagStravaRides
    //   (non-test callers: 1, the foreground sync); no_claim=none beyond protects
    func test_listedRidesAreTaggedWithTheConnectedAthlete() throws {
        let untagged = stored("1", daysAgo: 1, athlete: nil)
        let other = stored("2", daysAgo: 2, athlete: 8)
        let hk = stored("3", daysAgo: 3, source: "AppleWatch")
        let unlisted = stored("4", daysAgo: 4, athlete: nil)
        try context.save()
        DataPersistenceActor.tagStravaRides(ids: ["1", "2", "3"], athlete: 7, in: context)
        XCTAssertEqual(untagged.stravaAthleteId, 7)
        XCTAssertEqual(other.stravaAthleteId, 7, "a ride on this athlete's own list is this athlete's")
        XCTAssertNil(hk.stravaAthleteId)
        XCTAssertNil(unlisted.stravaAthleteId)
    }

    // Value: protects=deletion runs only with a known connected athlete and read_all granted
    //   (without it private rides are off the list); fails_when=either condition is dropped;
    //   why_new=review finding (private rides); seam=none; no_claim=the persistence of the values
    func test_deletionGate() {
        XCTAssertTrue(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, grantedScope: readAll))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, grantedScope: "read,activity:read"))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, grantedScope: nil))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: nil, grantedScope: readAll))
    }

    // Value: protects=the granted scope is read from Strava's callback, so an unticked read_all
    //   box turns deletion off; fails_when=the parse breaks (deletion silently never runs, or the
    //   gate sees the wrong value); why_new=review finding; seam=none; no_claim=Strava's real redirect
    func test_grantedScopeIsReadFromTheCallback() {
        let full = URL(string: "healthanalytics://cb?state=&code=abc&scope=read,activity:read_all,profile:read_all")!
        let unticked = URL(string: "healthanalytics://cb?state=&code=abc&scope=read,activity:read")!
        let none = URL(string: "healthanalytics://cb?code=abc")!
        XCTAssertTrue(StravaManager.grantsReadAll(StravaManager.grantedScope(fromCallback: full)))
        XCTAssertFalse(StravaManager.grantsReadAll(StravaManager.grantedScope(fromCallback: unticked)))
        XCTAssertNil(StravaManager.grantedScope(fromCallback: none))
    }

    // Value: protects=a sync whose Strava connection changed (reconnect, sign-out, another
    //   account) after it fetched the list tags and deletes nothing; fails_when=the athlete is
    //   read after the fetch again, so a mid-sync reconnect tags one account's rides as another's;
    //   why_new=fix-check finding (reconnect race); seam=none; no_claim=the generation bump sites
    func test_aChangedConnection_isNotTheSameConnection() {
        XCTAssertTrue(SyncManager.isSameStravaConnection(athleteAtFetch: 7, generationAtFetch: 3, athleteNow: 7, generationNow: 3))
        XCTAssertFalse(SyncManager.isSameStravaConnection(athleteAtFetch: 7, generationAtFetch: 3, athleteNow: 8, generationNow: 4))
        XCTAssertFalse(SyncManager.isSameStravaConnection(athleteAtFetch: 7, generationAtFetch: 3, athleteNow: 7, generationNow: 4), "reconnected as the same athlete still restarts")
        XCTAssertFalse(SyncManager.isSameStravaConnection(athleteAtFetch: nil, generationAtFetch: 3, athleteNow: nil, generationNow: 3))
    }

    // Value: protects=the 404 checks stop as soon as the connection changes, so later candidates
    //   aren't judged by the new login's token; fails_when=the loop ignores the check;
    //   why_new=fix-check finding; seam=confirmDeletedOnStrava (non-test callers: 1);
    //   no_claim=none beyond protects
    func test_confirmStops_whenTheConnectionChangesMidLoop() async {
        var asked: [String] = []
        var same = true
        let gone = await SyncManager.confirmDeletedOnStrava(["a", "b", "c"], stillSameConnection: { same }) { id in
            asked.append(id)
            if id == "a" { same = false }   // a reconnect lands while "a" is being checked
            return .gone
        }
        XCTAssertEqual(asked, ["a"])
        XCTAssertEqual(gone, [], "nothing judged across a connection change is deleted")
    }

    // Value: protects=a token refresh or profile fetch that started under an older connection
    //   doesn't overwrite the current login's tokens, athlete or FTP; fails_when=the generation
    //   check is dropped; why_new=fix-check findings (stale profile, refresh race); seam=none;
    //   no_claim=the call sites in refreshTokenIfNeeded / fetchAthleteProfile (network singleton)
    func test_staleProfileFetch_doesNotRecordItsAthlete() {
        XCTAssertTrue(StravaManager.isStillCurrentConnection(generationAtRequest: 2, generationNow: 2))
        XCTAssertFalse(StravaManager.isStillCurrentConnection(generationAtRequest: 2, generationNow: 3))
    }
}
