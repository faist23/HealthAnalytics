//
//  HealthDataObserverTests.swift
//  HealthAnalyticsTests
//
//  iOS backs off HealthKit background delivery for an app that leaves an observer
//  update uncompleted, so the completion must run on every outcome.
//

import HealthKit
import UIKit
import XCTest
@testable import HealthAnalytics

/// Records begin/end calls and holds the expiration handler so a test can fire it.
@MainActor
private final class FakeBackgroundTime {
    var nextID = UIBackgroundTaskIdentifier(rawValue: 42)
    private(set) var begun: [String] = []
    private(set) var ended: [UIBackgroundTaskIdentifier] = []
    private(set) var expire: (@MainActor @Sendable () -> Void)?

    var time: BackgroundTime {
        BackgroundTime(
            begin: { name, handler in
                self.begun.append(name)
                self.expire = handler
                return self.nextID
            },
            end: { self.ended.append($0) }
        )
    }
}

@MainActor
final class HealthDataObserverTests: XCTestCase {

    func test_handleUpdate_runsThePassForTheWake_thenCompletes() async {
        var ran: BackgroundPassWake?
        var completed = 0
        await HealthDataObserver.handleUpdate(
            wake: .hrvDelivery,
            run: { ran = $0 },
            completion: { completed += 1 }
        )
        XCTAssertEqual(ran, .hrvDelivery)
        XCTAssertEqual(completed, 1)
    }

    /// Review focus 4: the completion fires even when the pass ends early (locked,
    /// throttled, failed) — `run` returning is all the handler waits for.
    func test_handleUpdate_completesExactlyOnceWhenThePassReturnsImmediately() async {
        var completed = 0
        await HealthDataObserver.handleUpdate(wake: .workoutDelivery, run: { _ in }, completion: { completed += 1 })
        XCTAssertEqual(completed, 1)
    }

    /// The background-time expiry cancels the task awaiting the pass. `SingleFlight`
    /// returns that waiter at once while the flight's work runs on, so `run` returns
    /// early — and the completion must still run, exactly once.
    func test_handleUpdate_completesOnceWhenRunReturnsBecauseItsTaskWasCancelled() async {
        let flight = SingleFlight()
        let (release, releaseWork) = AsyncStream<Never>.makeStream()
        defer { releaseWork.finish() }
        var workFinished = false
        var completed = 0

        let waiter = Task { @MainActor in
            await HealthDataObserver.handleUpdate(
                wake: .hrvDelivery,
                run: { _ in
                    await flight.run {
                        for await _ in release {}
                        workFinished = true
                        return true
                    }
                },
                completion: { completed += 1 }
            )
        }
        waiter.cancel()
        await waiter.value

        XCTAssertEqual(completed, 1)
        XCTAssertFalse(workFinished, "The flight's work keeps running past the cancelled waiter")
    }

    func test_holdingBackgroundTime_beginsAndEndsOnceAroundThePass() async {
        let fake = FakeBackgroundTime()
        var ran: BackgroundPassWake?
        await HealthDataObserver.runHoldingBackgroundTime(wake: .hrvDelivery, run: { ran = $0 }, time: fake.time)
        XCTAssertEqual(ran, .hrvDelivery)
        XCTAssertEqual(fake.begun, ["patternPass"])
        XCTAssertEqual(fake.ended, [fake.nextID])
    }

    /// Expiry cancels the WAITING task: the hold returns (so the observer completes)
    /// while the flight's work runs on, and the identifier is ended exactly once even
    /// though both the expiration handler and the normal exit try to end it.
    func test_backgroundTimeExpiry_returnsPromptly_endsOnce_workRunsOn() async {
        let fake = FakeBackgroundTime()
        let flight = SingleFlight()
        let (release, releaseWork) = AsyncStream<Never>.makeStream()
        var workFinished = false
        var completed = 0

        let pending = Task { @MainActor in
            await HealthDataObserver.handleUpdate(
                wake: .hrvDelivery,
                run: { wake in
                    await HealthDataObserver.runHoldingBackgroundTime(wake: wake, run: { _ in
                        await flight.run {
                            for await _ in release {}
                            workFinished = true
                            return true
                        }
                    }, time: fake.time)
                },
                completion: { completed += 1 }
            )
        }
        var spins = 0
        while fake.expire == nil && spins < 10_000 { await Task.yield(); spins += 1 }
        guard fake.expire != nil else {
            XCTFail("the hold never registered an expiration handler")
            releaseWork.finish()
            await pending.value
            return
        }
        fake.expire?()
        await pending.value

        XCTAssertEqual(completed, 1)
        XCTAssertEqual(fake.ended, [fake.nextID], "End the identifier once, never twice")
        XCTAssertFalse(workFinished, "Expiry ends the wait, not the work")

        releaseWork.finish()
        await flight.run { true }   // joins the work if it is still running, so it has finished after this
        XCTAssertTrue(workFinished)
    }

    /// No background time granted (`.invalid`): the pass still runs, nothing is ended.
    func test_invalidBackgroundTask_isNeverEnded() async {
        let fake = FakeBackgroundTime()
        fake.nextID = .invalid
        await HealthDataObserver.runHoldingBackgroundTime(wake: .workoutDelivery, run: { _ in }, time: fake.time)
        XCTAssertTrue(fake.ended.isEmpty)
    }

    // Extended by /ship test coverage audit (Claude Code), pass 1.
    // Value: protects=the HRV type wakes as .hrvDelivery and workouts as .workoutDelivery (only HRV wakes record
    //   HRV-to-commit latency); fails_when=the pairs are swapped or a type is mislabeled; why_new=the set check
    //   passes with the wakes swapped; seam=none; no_claim=real delivery registration (device only)
    func test_observedTypes_coverHRVAndWorkouts() {
        let wakes = HealthDataObserver.observedTypes.map(\.wake)
        XCTAssertEqual(Set(wakes), [.hrvDelivery, .workoutDelivery])
        let byType = Dictionary(uniqueKeysWithValues: HealthDataObserver.observedTypes.map { ($0.type.identifier, $0.wake) })
        XCTAssertEqual(byType[HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue], .hrvDelivery)
        XCTAssertEqual(byType[HKObjectType.workoutType().identifier], .workoutDelivery)
    }
}
