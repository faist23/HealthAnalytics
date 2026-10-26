//
//  SingleFlightTests.swift
//  HealthAnalyticsTests
//
//  Pins the property the Coach hand-off depends on: work started by a view's
//  `.task` must finish even when SwiftUI cancels that task.
//

import XCTest
@testable import HealthAnalytics

@MainActor
final class SingleFlightTests: XCTestCase {

    @MainActor
    private final class Probe {
        var runs = 0
        var finished = false
        var sawCancellation = false
    }

    /// Long enough that a second caller arrives while the first run is in flight.
    private func slowWork(_ probe: Probe) -> @MainActor () async -> Void {
        {
            probe.runs += 1
            try? await Task.sleep(for: .milliseconds(100))
            probe.sawCancellation = Task.isCancelled
            probe.finished = true
        }
    }

    /// A tab swipe cancels the view task that asked for pattern analysis. If that
    /// cancellation reached the work, MasterCoachEngine's LLM call would throw and
    /// the heuristic paragraph would be cached for the rest of the day.
    func test_run_callerCancellationDoesNotReachTheWork() async {
        let flight = SingleFlight()
        let probe = Probe()
        let caller = Task { await flight.run(slowWork(probe)) }
        caller.cancel()
        await caller.value
        await flight.run(slowWork(probe))   // joins the still-running work

        XCTAssertTrue(probe.finished)
        XCTAssertEqual(probe.runs, 1, "The cancelled caller's work must keep running, not restart")
        XCTAssertFalse(probe.sawCancellation, "The caller's cancellation must not reach the work")
    }

    /// iOS cancels a background task when its time budget expires, and the handler must
    /// return promptly then. Cancellation ends the caller's wait; the work carries on.
    func test_run_cancelledCallerStopsWaitingBeforeTheWorkFinishes() async {
        let flight = SingleFlight()
        let probe = Probe()
        let caller = Task { await flight.run(slowWork(probe)) }
        caller.cancel()
        await caller.value

        XCTAssertFalse(probe.finished, "A cancelled caller must stop waiting instead of blocking on the work")
    }

    /// Recovery-tab appears in quick succession must not start overlapping analyses.
    func test_run_overlappingCallersJoinOneRun() async {
        let flight = SingleFlight()
        let probe = Probe()
        async let first: Void = flight.run(slowWork(probe))
        async let second: Void = flight.run(slowWork(probe))
        _ = await (first, second)

        XCTAssertEqual(probe.runs, 1)
        XCTAssertTrue(probe.finished)
    }

    /// Joining is only for overlap; a request after the run finished must run again.
    func test_run_afterCompletionRunsAgain() async {
        let flight = SingleFlight()
        let probe = Probe()
        await flight.run(slowWork(probe))
        await flight.run(slowWork(probe))

        XCTAssertEqual(probe.runs, 2)
    }

    func test_shielded_callerCancellationDoesNotReachTheWork() async {
        let probe = Probe()
        let caller = Task { await SingleFlight.shielded(slowWork(probe)) }
        caller.cancel()
        await caller.value
        XCTAssertFalse(probe.finished, "A cancelled caller must stop waiting")

        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(probe.finished, "The shielded work must still run to completion")
        XCTAssertFalse(probe.sawCancellation)
    }
}
