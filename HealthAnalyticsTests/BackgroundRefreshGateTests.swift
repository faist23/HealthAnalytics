//
//  BackgroundRefreshGateTests.swift
//  HealthAnalyticsTests
//
//  The background pass's HealthKit-only workout upsert and the foreground sync must not
//  interleave: each checks the store for the other's copy of a ride before inserting, so
//  two upserts in flight at once can both miss and store the ride twice.
//

import XCTest
@testable import HealthAnalytics

@MainActor
final class BackgroundRefreshGateTests: XCTestCase {

    /// A foreground sync is running: the background refresh does nothing (no fetch, no
    /// stamp). The sync is about to store the same window with the Strava copies.
    func test_run_whileSyncing_skipsTheWork() async throws {
        let gate = BackgroundRefreshGate()
        var ran = false

        let didRun = try await gate.run(skippingWhile: true) { ran = true }

        XCTAssertFalse(didRun)
        XCTAssertFalse(ran)
    }

    func test_run_whenNotSyncing_runsTheWork() async throws {
        let gate = BackgroundRefreshGate()
        var ran = false

        let didRun = try await gate.run(skippingWhile: false) { ran = true }

        XCTAssertTrue(didRun)
        XCTAssertTrue(ran)
    }

    /// A foreground sync that starts while a background refresh is upserting waits for
    /// it to finish before its own upsert.
    func test_waitForInFlight_returnsOnlyAfterTheBackgroundRefreshFinishes() async throws {
        let gate = BackgroundRefreshGate()
        let (release, releaseWork) = AsyncStream<Never>.makeStream()
        var backgroundFinished = false
        var started = false

        let background = Task { @MainActor in
            try await gate.run(skippingWhile: false) {
                started = true
                for await _ in release {}
                backgroundFinished = true
            }
        }
        while !started { await Task.yield() }

        var foregroundSawFinished: Bool?
        let foreground = Task { @MainActor in
            await gate.waitForInFlight()
            foregroundSawFinished = backgroundFinished
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(foregroundSawFinished, "The foreground must still be waiting")

        releaseWork.finish()
        await foreground.value
        _ = try await background.value

        XCTAssertEqual(foregroundSawFinished, true)
    }

    /// A failed refresh still releases the foreground, and is cleared so the next one runs.
    func test_failedRefresh_releasesTheWaiterAndIsCleared() async throws {
        struct Boom: Error {}
        let gate = BackgroundRefreshGate()

        do {
            try await gate.run(skippingWhile: false) { throw Boom() }
            XCTFail("The error must reach the caller")
        } catch is Boom {}
        await gate.waitForInFlight()

        var ranAgain = false
        try await gate.run(skippingWhile: false) { ranAgain = true }
        XCTAssertTrue(ranAgain)
    }
}
