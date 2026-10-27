//
//  BackgroundPatternPassTests.swift
//  HealthAnalyticsTests
//
//  The pass's ordering, skip rules, abandon rule and stamp, against fake steps and a
//  fake clock — no singleton, no HealthKit.
//

import XCTest
@testable import HealthAnalytics

@MainActor
private final class FakeClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
private final class FakeSteps: BackgroundPassSteps {
    var protectedDataAvailable = true
    var lastRun: Date?
    var analyzeError: Error?
    var refreshWorkoutsError: Error?
    /// Advances the fake clock during analysis, before the gate is asked.
    var advanceDuringAnalysis: TimeInterval = 0
    var newestHRV: Date?
    let clock: FakeClock

    private(set) var calls: [String] = []
    private(set) var stamped: Date?
    private(set) var gateResult: Bool?

    init(clock: FakeClock) { self.clock = clock }

    func isProtectedDataAvailable() -> Bool { protectedDataAvailable }
    func lastPatternRun() -> Date? { lastRun }
    func refreshWorkouts() async throws {
        calls.append("refreshWorkouts")
        if let refreshWorkoutsError { throw refreshWorkoutsError }
    }
    func finalizeScoreRows() async { calls.append("finalizeScoreRows") }
    func analyzePatterns(commitGate: @escaping @Sendable () async -> Bool) async throws {
        calls.append("analyze")
        if let analyzeError { throw analyzeError }
        clock.now = clock.now.addingTimeInterval(advanceDuringAnalysis)
        let ok = await commitGate()
        gateResult = ok
        if !ok { throw PatternAnalysisError.commitDeclined }
        calls.append("commit")
    }
    func stamp(_ startedAt: Date) { calls.append("stamp"); stamped = startedAt }
    func refreshCoachIfForeground() async { calls.append("coach") }
    func newestHRVSampleDate() async -> Date? { newestHRV }
}

private struct SomeHealthKitError: Error {}

@MainActor
final class BackgroundPatternPassTests: XCTestCase {
    private var defaults: UserDefaults!
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: "BackgroundPatternPassTests")
        defaults.removePersistentDomain(forName: "BackgroundPatternPassTests")
    }

    private func makePass(_ steps: FakeSteps, _ clock: FakeClock) -> (BackgroundPatternPass, BackgroundPassLog) {
        let log = BackgroundPassLog(defaults: defaults)
        let pass = BackgroundPatternPass(steps: steps, log: log, now: { MainActor.assumeIsolated { clock.now } })
        return (pass, log)
    }

    func test_completedPass_runsStepsInOrder_andStampsTheStartTime() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringAnalysis = 20
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(steps.calls, ["refreshWorkouts", "finalizeScoreRows", "analyze", "commit", "stamp", "coach"])
        XCTAssertEqual(steps.stamped, t0, "The stamp describes the data the run read: its start, not its end")
        XCTAssertEqual(log.count(.completed), 1)
    }

    func test_locked_skipsEveryStep() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.protectedDataAvailable = false
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .skippedLocked)
        XCTAssertTrue(steps.calls.isEmpty)
        XCTAssertEqual(log.count(.skippedLocked), 1)
    }

    /// Review focus 2: a burst of deliveries inside the 5-minute window does nothing.
    func test_burstWithinThrottleWindow_isThrottled() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.lastRun = t0.addingTimeInterval(-60)
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .throttled)
        XCTAssertTrue(steps.calls.isEmpty)
        XCTAssertEqual(log.count(.throttled), 1)
    }

    func test_runSpanningASuspension_isAbandoned_withoutStampOrCommit() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringAnalysis = BackgroundPatternPass.maxDuration + 1
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .abandoned)
        XCTAssertEqual(steps.gateResult, false)
        XCTAssertNil(steps.stamped, "An abandoned run must not stamp, so the next trigger runs fresh")
        XCTAssertFalse(steps.calls.contains("commit"))
        XCTAssertFalse(steps.calls.contains("coach"))
        XCTAssertEqual(log.count(.abandoned), 1)
    }

    /// Review focus 3: the clock moving backwards mid-run is not proof of freshness.
    func test_clockMovedBackwardsMidRun_isAbandoned() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringAnalysis = -3600
        let (pass, _) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .abandoned)
        XCTAssertNil(steps.stamped)
    }

    /// Review focus 4: HealthKit failing is silent and unstamped.
    func test_analysisFailure_isFailed_withoutStamp() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.analyzeError = SomeHealthKitError()
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .failed)
        XCTAssertNil(steps.stamped)
        XCTAssertEqual(log.count(.failed), 1)
    }

    /// Fewer than 60 days of history: nothing to keep alive, safe to throttle (as the
    /// foreground does).
    func test_insufficientData_isCompleted_andStamped() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.analyzeError = PatternAnalysisError.insufficientData
        let (pass, _) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(steps.stamped, t0)
    }

    func test_workoutRefreshFailure_doesNotBlockDetection() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.refreshWorkoutsError = SomeHealthKitError()
        let (pass, _) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertTrue(steps.calls.contains("analyze"))
    }

    func test_completedPass_recordsLatencyFromTheNewestHRVSample() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.newestHRV = t0.addingTimeInterval(-600)
        steps.advanceDuringAnalysis = 15
        let (pass, log) = makePass(steps, clock)

        _ = await pass.run()

        XCTAssertEqual(log.lastLatency ?? -1, 615, accuracy: 0.001)
    }

    func test_log_countsWakesPerTrigger() {
        let log = BackgroundPassLog(defaults: defaults)
        log.recordWake(.hrvDelivery)
        log.recordWake(.hrvDelivery)
        log.recordWake(.appRefresh)
        XCTAssertEqual(log.count(.hrvDelivery), 2)
        XCTAssertEqual(log.count(.appRefresh), 1)
        XCTAssertEqual(log.count(.workoutDelivery), 0)
    }

    func test_isWithinBudget_edges() {
        XCTAssertTrue(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0))
        XCTAssertTrue(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(BackgroundPatternPass.maxDuration)))
        XCTAssertFalse(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(BackgroundPatternPass.maxDuration + 0.001)))
        XCTAssertFalse(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(-1)))
    }
}
