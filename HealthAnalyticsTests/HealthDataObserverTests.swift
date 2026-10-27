//
//  HealthDataObserverTests.swift
//  HealthAnalyticsTests
//
//  iOS backs off HealthKit background delivery for an app that leaves an observer
//  update uncompleted, so the completion must run on every outcome.
//

import XCTest
@testable import HealthAnalytics

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

    func test_observedTypes_coverHRVAndWorkouts() {
        let wakes = HealthDataObserver.observedTypes.map(\.wake)
        XCTAssertEqual(Set(wakes), [.hrvDelivery, .workoutDelivery])
    }
}
