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
    /// Advances the fake clock inside the workout refresh / daily load refresh (a
    /// suspension mid-step).
    var advanceDuringRefresh: TimeInterval = 0
    var advanceDuringLoadRefresh: TimeInterval = 0
    /// Advances the fake clock during analysis, before the gate is asked.
    var advanceDuringAnalysis: TimeInterval = 0
    var newestHRV: Date?
    /// Advances the fake clock inside the newest-HRV query, after the commit.
    var advanceDuringHRVQuery: TimeInterval = 0
    let clock: FakeClock

    private(set) var calls: [String] = []
    private(set) var stamped: Date?
    private(set) var gateResult: Bool?

    init(clock: FakeClock) { self.clock = clock }

    func isProtectedDataAvailable() -> Bool { protectedDataAvailable }
    func lastPatternRun() -> Date? { lastRun }
    func refreshWorkouts() async throws {
        calls.append("refreshWorkouts")
        clock.now = clock.now.addingTimeInterval(advanceDuringRefresh)
        if let refreshWorkoutsError { throw refreshWorkoutsError }
    }
    func refreshRecentDailyLoads() async {
        calls.append("refreshRecentDailyLoads")
        clock.now = clock.now.addingTimeInterval(advanceDuringLoadRefresh)
    }
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
    func newestHRVSampleDate() async -> Date? {
        calls.append("newestHRV")
        clock.now = clock.now.addingTimeInterval(advanceDuringHRVQuery)
        return newestHRV
    }
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

    private func makePass(
        _ steps: FakeSteps, _ clock: FakeClock, wake: BackgroundPassWake = .hrvDelivery
    ) -> (BackgroundPatternPass, BackgroundPassLog) {
        let log = BackgroundPassLog(defaults: defaults)
        let pass = BackgroundPatternPass(
            steps: steps, log: log, wake: wake, now: { MainActor.assumeIsolated { clock.now } }
        )
        return (pass, log)
    }

    func test_completedPass_runsStepsInOrder_andStampsTheStartTime() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringAnalysis = 20
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(steps.calls, ["refreshWorkouts", "refreshRecentDailyLoads", "analyze", "commit", "stamp", "newestHRV", "coach"])
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
        // Extended by /ship test coverage audit (Claude Code), pass 1.
        // Value: protects=the debug screen's Last pass row reads back what the pass recorded; fails_when=record stops
        //   writing, or reads a different key than, lastOutcome/lastOutcomeAt; why_new=only per-outcome counts were
        //   read back; seam=none; no_claim=the SwiftUI rendering of the row
        XCTAssertEqual(log.lastOutcome, .skippedLocked)
        XCTAssertEqual(log.lastOutcomeAt, t0)
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

    /// A pass frozen inside the workout refresh resumes past its budget. Detecting now
    /// would read a store refreshed before the freeze; stop before the load refresh and analysis.
    func test_suspensionDuringWorkoutRefresh_isAbandoned_beforeLoadRefreshOrAnalysis() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringRefresh = BackgroundPatternPass.maxDuration + 1
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .abandoned)
        XCTAssertEqual(steps.calls, ["refreshWorkouts"])
        XCTAssertNil(steps.stamped)
        XCTAssertEqual(log.count(.abandoned), 1)
    }

    func test_suspensionDuringDailyLoadRefresh_isAbandoned_beforeAnalysis() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringLoadRefresh = BackgroundPatternPass.maxDuration + 1
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .abandoned)
        XCTAssertEqual(steps.calls, ["refreshWorkouts", "refreshRecentDailyLoads"])
        XCTAssertNil(steps.stamped)
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

    /// Latency runs from the newest HRV sample to the commit, not to the end of the
    /// HRV query that follows it.
    func test_completedPass_recordsLatencyFromTheNewestHRVSampleToTheCommit() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.newestHRV = t0.addingTimeInterval(-600)
        steps.advanceDuringAnalysis = 15
        steps.advanceDuringHRVQuery = 30
        let (pass, log) = makePass(steps, clock, wake: .hrvDelivery)

        _ = await pass.run()

        XCTAssertEqual(log.lastLatency ?? -1, 615, accuracy: 0.001)
    }

    /// Only an HRV delivery measures HRV-to-commit latency; an app-refresh (or workout)
    /// wake must not overwrite it with a gap that has nothing to do with delivery.
    func test_appRefreshPass_recordsNoLatency() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.newestHRV = t0.addingTimeInterval(-6 * 3600)
        let (pass, log) = makePass(steps, clock, wake: .appRefresh)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertNil(log.lastLatency)
        XCTAssertFalse(steps.calls.contains("newestHRV"), "No latency to record, so no HRV query")
    }

    func test_log_countsWakesPerTrigger() {
        let log = BackgroundPassLog(defaults: defaults)
        log.recordWake(.hrvDelivery, appActive: false)
        log.recordWake(.hrvDelivery, appActive: false)
        log.recordWake(.appRefresh, appActive: false)
        XCTAssertEqual(log.count(.hrvDelivery), 2)
        XCTAssertEqual(log.count(.appRefresh), 1)
        XCTAssertEqual(log.count(.workoutDelivery), 0)
    }

    /// iOS fires every observer query once when it is registered, so a cold launch in
    /// the foreground "delivers". Those wakes count apart, never as delivery evidence.
    func test_log_countsWakesWhileActiveSeparately() {
        let log = BackgroundPassLog(defaults: defaults)
        log.recordWake(.hrvDelivery, appActive: true)
        log.recordWake(.hrvDelivery, appActive: true)
        log.recordWake(.hrvDelivery, appActive: false)
        log.recordWake(.workoutDelivery, appActive: true)
        XCTAssertEqual(log.count(.hrvDelivery), 1)
        XCTAssertEqual(log.count(.hrvDelivery, whileActive: false), 1)
        XCTAssertEqual(log.count(.hrvDelivery, whileActive: true), 2)
        XCTAssertEqual(log.count(.workoutDelivery), 0)
        XCTAssertEqual(log.count(.workoutDelivery, whileActive: true), 1)
    }

    /// iOS fires every observer query once when it registers, so each foreground cold
    /// launch "delivers". A wake while the app is in the foreground must not run a full
    /// pass: it records `skippedForeground` and the foreground's own refresh does the work.
    func test_skipIfForeground_inForeground_recordsSkippedForeground() {
        let log = BackgroundPassLog(defaults: defaults)

        let skipped = BackgroundPatternPass.skipIfForeground(appInForeground: true, log: log, at: t0)

        XCTAssertTrue(skipped)
        XCTAssertEqual(log.count(.skippedForeground), 1)
        XCTAssertEqual(log.lastOutcome, .skippedForeground)
        XCTAssertEqual(log.lastOutcomeAt, t0)
    }

    func test_skipIfForeground_inBackground_runsAndRecordsNothing() {
        let log = BackgroundPassLog(defaults: defaults)

        let skipped = BackgroundPatternPass.skipIfForeground(appInForeground: false, log: log, at: t0)

        XCTAssertFalse(skipped)
        XCTAssertEqual(log.count(.skippedForeground), 0)
        XCTAssertNil(log.lastOutcome)
    }

    func test_isWithinBudget_edges() {
        XCTAssertTrue(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0))
        XCTAssertTrue(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(BackgroundPatternPass.maxDuration)))
        XCTAssertFalse(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(BackgroundPatternPass.maxDuration + 0.001)))
        XCTAssertFalse(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(-1)))
    }
}
