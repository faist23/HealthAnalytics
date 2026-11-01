//
//  StravaDeletedRidesTests.swift
//  HealthAnalyticsTests
//
//  A ride deleted on Strava used to stay in the store and keep adding load. Each sync now
//  compares stored Strava rides with Strava's newest page of activities and removes the
//  ones Strava no longer lists, only for the athlete whose rides the store holds.
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

    private func listing(_ id: String, daysAgo: Double) -> DataPersistenceActor.StravaListing {
        .init(id: id, startDate: day(daysAgo))
    }

    private func storedIDs() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<StoredWorkout>()).map(\.id))
    }

    // Value: protects=a ride deleted on Strava stops counting toward load; fails_when=sync
    //   goes back to insert/update only; why_new=nothing ever removed a Strava ride;
    //   seam=removeRidesDeletedOnStrava (non-test callers: 1, the foreground sync);
    //   no_claim=Strava's real list (synthetic listings)
    func test_rideMissingFromAFullPage_insideItsSpan_isRemoved() throws {
        stored("1", daysAgo: 1); stored("2", daysAgo: 2); stored("3", daysAgo: 3)
        try context.save()
        // A full page spanning days 1–3; ride 2 was deleted on Strava.
        let removed = DataPersistenceActor.removeRidesDeletedOnStrava(
            listed: [listing("1", daysAgo: 1), listing("3", daysAgo: 3)], pageWasFull: true, in: context)
        XCTAssertEqual(removed, ["2"])
        XCTAssertEqual(try storedIDs(), ["1", "3"])
    }

    // Value: protects=rides older than a full page's span are kept (the page says nothing about
    //   them), and a ride dated exactly at the page's oldest is kept; fails_when=the span check
    //   is dropped and a sync deletes most of the history; why_new=new rule; seam=removeRidesDeletedOnStrava
    //   (non-test callers: 1); no_claim=none beyond protects
    func test_ridesAtOrBeyondAFullPagesOldestDate_areKept() throws {
        stored("1", daysAgo: 1); stored("old", daysAgo: 30); stored("tie", daysAgo: 5)
        try context.save()
        let removed = DataPersistenceActor.removeRidesDeletedOnStrava(
            listed: [listing("1", daysAgo: 1), listing("x", daysAgo: 5)], pageWasFull: true, in: context)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(try storedIDs(), ["1", "old", "tie"])
    }

    // Value: protects=with fewer activities than one page the list is everything, so any stored
    //   Strava ride not on it is gone; HealthKit rides are never touched; fails_when=a partial page
    //   is treated as a span, or non-Strava rows are deleted; why_new=new rule;
    //   seam=removeRidesDeletedOnStrava (non-test callers: 1); no_claim=none beyond protects
    func test_partialPageIsTheWholeHistory_andHealthKitRidesAreNeverTouched() throws {
        stored("1", daysAgo: 1); stored("gone", daysAgo: 400); stored("hk-uuid", daysAgo: 2, source: "AppleWatch")
        try context.save()
        let removed = DataPersistenceActor.removeRidesDeletedOnStrava(
            listed: [listing("1", daysAgo: 1)], pageWasFull: false, in: context)
        XCTAssertEqual(removed, ["gone"])
        XCTAssertEqual(try storedIDs(), ["1", "hk-uuid"])
    }

    // Value: protects=an empty list never deletes (a glitch or an empty account must not wipe the
    //   store); fails_when=the empty guard is removed; why_new=new guard; seam=removeRidesDeletedOnStrava
    //   (non-test callers: 1); no_claim=none beyond protects
    func test_emptyList_deletesNothing() throws {
        stored("1", daysAgo: 1)
        try context.save()
        XCTAssertTrue(DataPersistenceActor.removeRidesDeletedOnStrava(listed: [], pageWasFull: false, in: context).isEmpty)
        XCTAssertEqual(try storedIDs(), ["1"])
    }

    // Value: protects=a removed ride's intent label goes with it; fails_when=labels are left
    //   pointing at deleted workouts; why_new=new; seam=removeRidesDeletedOnStrava (non-test
    //   callers: 1); no_claim=none beyond protects
    func test_removedRidesIntentLabel_isRemovedToo() throws {
        stored("1", daysAgo: 1); stored("2", daysAgo: 2)
        context.insert(StoredIntentLabel(workoutId: "2", intent: .long, confidence: 0.9, source: .heuristic))
        context.insert(StoredIntentLabel(workoutId: "1", intent: .long, confidence: 0.9, source: .heuristic))
        try context.save()
        _ = DataPersistenceActor.removeRidesDeletedOnStrava(listed: [listing("1", daysAgo: 1)], pageWasFull: false, in: context)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<StoredIntentLabel>()).map(\.workoutId)), ["1"])
    }

    // Value: protects=rides are removed only while the connected Strava athlete is the one whose
    //   rides the store holds; fails_when=switching accounts deletes the other account's rides;
    //   why_new=new guard; seam=none; no_claim=the persistence of either id (UserDefaults)
    func test_reconcileOnlyForTheBaselineAthlete() {
        XCTAssertTrue(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, baseline: 7))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 8, baseline: 7))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: nil, baseline: 7))
        XCTAssertFalse(SyncManager.mayRemoveRidesDeletedOnStrava(connected: 7, baseline: nil))
    }
}
