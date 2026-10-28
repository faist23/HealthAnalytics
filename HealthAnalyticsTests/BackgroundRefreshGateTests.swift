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

    // MARK: - Joining an in-flight refresh

    /// A second refresh requested while one runs (an HRV and a workout delivery back to
    /// back) joins it: the work runs once and both callers hear it ran.
    func test_run_whileOneIsInFlight_joinsIt_workRunsOnce() async throws {
        let gate = BackgroundRefreshGate()
        let (release, releaseWork) = AsyncStream<Never>.makeStream()
        var runs = 0

        let first = Task { @MainActor in
            try await gate.run(skippingWhile: false) {
                runs += 1
                for await _ in release {}
            }
        }
        while runs == 0 { await Task.yield() }
        let second = Task { @MainActor in
            try await gate.run(skippingWhile: false) { runs += 1 }
        }
        for _ in 0..<20 { await Task.yield() }

        releaseWork.finish()
        let firstRan = try await first.value
        let secondRan = try await second.value

        XCTAssertEqual(runs, 1, "The joiner must not start a second upsert")
        XCTAssertTrue(firstRan)
        XCTAssertTrue(secondRan)
    }

    /// The in-flight refresh fails: the joiner sees the same error, not a silent success.
    func test_run_joinerOfAFailingRefresh_getsItsError() async {
        struct Boom: Error {}
        let gate = BackgroundRefreshGate()
        let (release, releaseWork) = AsyncStream<Never>.makeStream()
        var started = false

        let first = Task { @MainActor in
            try await gate.run(skippingWhile: false) {
                started = true
                for await _ in release {}
                throw Boom()
            }
        }
        while !started { await Task.yield() }
        let second = Task { @MainActor in
            try await gate.run(skippingWhile: false) {}
        }
        for _ in 0..<20 { await Task.yield() }

        releaseWork.finish()
        let firstResult = await first.result
        let secondResult = await second.result

        XCTAssertThrowsError(try firstResult.get()) { XCTAssertTrue($0 is Boom) }
        XCTAssertThrowsError(try secondResult.get()) { XCTAssertTrue($0 is Boom, "The joiner must get the in-flight error") }
    }
}
