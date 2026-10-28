//
//  BackgroundPatternPass.swift
//  HealthAnalytics
//
//  The one thing background triggers (HealthKit delivery, app refresh) run. A wake
//  while the app is in the foreground is skipped before the pass starts. Order:
//  protected-data guard → throttle → HealthKit-only workout refresh → score-row
//  finalization → detection behind a commit gate → stamp (start time) → Coach only
//  if the app is in the foreground. Never posts DataSyncCompleted, never calls Strava.
//

import Foundation
import HealthKit
import SwiftData
import UIKit

enum BackgroundPassWake: String, CaseIterable, Sendable {
    case hrvDelivery, workoutDelivery, appRefresh
}

enum BackgroundPassOutcome: String, CaseIterable, Sendable {
    case skippedForeground, skippedLocked, throttled, completed, abandoned, failed
}

@MainActor
protocol BackgroundPassSteps {
    func isProtectedDataAvailable() -> Bool
    func lastPatternRun() -> Date?
    func refreshWorkouts() async throws
    func finalizeScoreRows() async
    /// Detects, then commits only if `commitGate` returns true; throws
    /// `PatternAnalysisError.commitDeclined` when it refuses.
    func analyzePatterns(commitGate: @escaping @Sendable () async -> Bool) async throws
    func stamp(_ startedAt: Date)
    func refreshCoachIfForeground() async
    func newestHRVSampleDate() async -> Date?
}

@MainActor
final class BackgroundPatternPass {
    /// A background budget is ~30s. A run whose detection finishes later than this
    /// after it started spanned a suspension: some reads predate the freeze, some
    /// follow it, so its verdict describes no real moment. Discard it.
    nonisolated static let maxDuration: TimeInterval = 2 * 60

    private let steps: BackgroundPassSteps
    private let log: BackgroundPassLog
    /// What woke the app. Only an HRV delivery measures HRV-to-commit latency.
    private let wake: BackgroundPassWake
    private let now: @Sendable () -> Date

    init(
        steps: BackgroundPassSteps,
        log: BackgroundPassLog,
        wake: BackgroundPassWake,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.steps = steps
        self.log = log
        self.wake = wake
        self.now = now
    }

    @discardableResult
    func run() async -> BackgroundPassOutcome {
        let outcome = await perform()
        log.record(outcome, at: now())
        return outcome
    }

    private func perform() async -> BackgroundPassOutcome {
        guard steps.isProtectedDataAvailable() else { return .skippedLocked }
        let startedAt = now()
        guard ReadinessRepository.shouldRunPatternAnalysis(
            lastRun: steps.lastPatternRun(), trigger: .background, now: startedAt
        ) else { return .throttled }

        // Neither step's failure may block detection: a stale store is still checked by
        // the gate. A suspension inside either step ends the pass, though: a run frozen
        // there resumes past its budget, and continuing would hold the flight through a
        // whole detection only for the gate to refuse it, while a wake arriving meanwhile
        // joins that doomed run (its joiners rerun once; see `SingleFlight.run`).
        try? await steps.refreshWorkouts()
        guard Self.isWithinBudget(startedAt: startedAt, now: now()) else { return .abandoned }
        await steps.finalizeScoreRows()
        guard Self.isWithinBudget(startedAt: startedAt, now: now()) else { return .abandoned }

        let clock = now
        do {
            try await steps.analyzePatterns(commitGate: {
                Self.isWithinBudget(startedAt: startedAt, now: clock())
            })
        } catch PatternAnalysisError.commitDeclined {
            return .abandoned
        } catch PatternAnalysisError.insufficientData {
            // < 60 days of history: nothing to keep alive, safe to throttle (as the
            // foreground does).
            steps.stamp(startedAt)
            return .completed
        } catch {
            // Silent in the background (HealthKit refuses reads while locked, or
            // isn't authorized). Unstamped, so the next trigger retries.
            return .failed
        }

        // The commit just happened; the HRV query below must not count toward latency.
        let committedAt = now()
        steps.stamp(startedAt)
        // An app-refresh or workout wake would overwrite the HRV-delivery latency with a
        // gap that says nothing about delivery.
        if wake == .hrvDelivery, let newest = await steps.newestHRVSampleDate() {
            log.recordLatency(committedAt.timeIntervalSince(newest))
        }
        await steps.refreshCoachIfForeground()
        return .completed
    }

    /// A wake while the app is in the foreground skips the pass and records
    /// `skippedForeground`. iOS fires every observer query once when it registers, so
    /// each foreground cold launch "delivers"; the foreground's own sync and refresh do
    /// that work (with Strava data). App-refresh wakes are background by construction.
    /// Returns true when the caller must not run the pass.
    static func skipIfForeground(appInForeground: Bool, log: BackgroundPassLog, at date: Date) -> Bool {
        guard appInForeground else { return false }
        log.record(.skippedForeground, at: date)
        return true
    }

    /// Inside the budget and not before the start (a clock moved backwards proves
    /// nothing about freshness).
    nonisolated static func isWithinBudget(startedAt: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(startedAt)
        return elapsed >= 0 && elapsed <= maxDuration
    }
}

/// Counters for the debug "Background Pass" screen: how often each trigger wakes the
/// app, how each pass ends, and how long after the newest HRV sample a pass committed.
@MainActor
struct BackgroundPassLog {
    let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    static var standard: BackgroundPassLog { BackgroundPassLog(defaults: .standard) }

    /// iOS fires each observer query once when it is registered, so a cold launch in the
    /// foreground "delivers" too. Wakes while the app is active count apart and never
    /// read as background-delivery evidence; `count(_:)` is the not-active count.
    func recordWake(_ wake: BackgroundPassWake, appActive: Bool) {
        increment(Self.wakeKey(wake, whileActive: appActive))
    }

    func record(_ outcome: BackgroundPassOutcome, at date: Date) {
        increment("backgroundPass.outcome.\(outcome.rawValue)")
        defaults.set(outcome.rawValue, forKey: "backgroundPass.lastOutcome")
        defaults.set(date, forKey: "backgroundPass.lastOutcomeAt")
    }

    func recordLatency(_ seconds: TimeInterval) {
        defaults.set(seconds, forKey: "backgroundPass.lastLatency")
    }

    func count(_ wake: BackgroundPassWake, whileActive: Bool = false) -> Int {
        defaults.integer(forKey: Self.wakeKey(wake, whileActive: whileActive))
    }
    func count(_ outcome: BackgroundPassOutcome) -> Int { defaults.integer(forKey: "backgroundPass.outcome.\(outcome.rawValue)") }

    var lastOutcome: BackgroundPassOutcome? {
        defaults.string(forKey: "backgroundPass.lastOutcome").flatMap(BackgroundPassOutcome.init(rawValue:))
    }
    var lastOutcomeAt: Date? { defaults.object(forKey: "backgroundPass.lastOutcomeAt") as? Date }
    var lastLatency: TimeInterval? { defaults.object(forKey: "backgroundPass.lastLatency") as? TimeInterval }

    private static func wakeKey(_ wake: BackgroundPassWake, whileActive: Bool) -> String {
        "backgroundPass.wake.\(wake.rawValue)" + (whileActive ? ".whileActive" : "")
    }

    private func increment(_ key: String) { defaults.set(defaults.integer(forKey: key) + 1, forKey: key) }
}

/// Production steps. Not unit-tested (singleton + HealthKit); see the device checklist.
@MainActor
struct LiveBackgroundPassSteps: BackgroundPassSteps {
    let repository: ReadinessRepository
    let container: ModelContainer

    func isProtectedDataAvailable() -> Bool { UIApplication.shared.isProtectedDataAvailable }

    func lastPatternRun() -> Date? {
        UserDefaults.standard.object(forKey: "lastPatternAnalysisDate") as? Date
    }

    func refreshWorkouts() async throws { try await SyncManager.shared.refreshWorkoutsFromHealthKit() }

    /// Recomputes rows but never advances `scoresFinalizedThrough`: before the Strava
    /// sync the store may hold only the HealthKit copy of yesterday's ride, and the next
    /// foreground refresh recomputes the same days with the Strava data.
    func finalizeScoreRows() async {
        await repository.finalizeScoreRows(modelContext: container.mainContext, advancesMarker: false)
    }

    func analyzePatterns(commitGate: @escaping @Sendable () async -> Bool) async throws {
        try await repository.analyzePatternsForBackgroundPass(container: container, commitGate: commitGate)
    }

    func stamp(_ startedAt: Date) { UserDefaults.standard.set(startedAt, forKey: "lastPatternAnalysisDate") }

    func refreshCoachIfForeground() async {
        guard repository.isAppInForeground() else { return }
        await repository.refreshIfNecessary(modelContext: container.mainContext)
    }

    func newestHRVSampleDate() async -> Date? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRateVariabilitySDNN),
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first?.endDate)
            }
            HKHealthStore().execute(query)
        }
    }
}
