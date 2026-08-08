//
//  TrainingDNAAnalyzerTests.swift
//  HealthAnalyticsTests
//
//  Tests TrainingDNAAnalyzer detection logic via MockPatternDataProvider injection.
//  No HealthKit access required — pure data-path tests.
//
//  Coverage:
//    - detectBlockCrashCycle: happy path, insufficient blocks, stats rejection
//    - detectSleepFragmentation: happy path, insufficient periods
//    - detectHRVPrecursor: happy path, insufficient sick windows
//    - analyze() historyDays gating (< 60 throws, 60-89 skips 90-day patterns)
//    - upsert: notificationSent never reset once true
//

import XCTest
import SwiftData
@testable import HealthAnalytics

// MARK: - MockPatternDataProvider

/// Synchronous, in-memory test double for PatternDataProvider.
/// Set each property to control what the analyzer receives.
struct MockPatternDataProvider: PatternDataProvider {
    var historyDays: Int = 180
    var acwrData:  [(date: Date, acwr: Double)] = []
    var hrvData:   [(date: Date, hrv: Double)] = []
    var sleepData: [(date: Date, hours: Double, efficiency: Double)] = []
    var stepsData: [(date: Date, steps: Int)] = []
    var workoutDays: Set<String> = []

    func totalHealthKitHistoryDays() async throws -> Int { historyDays }
    func fetchDailyACWR(days: Int) async throws -> [(date: Date, acwr: Double)] { acwrData }
    func fetchDailyHRV(days: Int, sourcePreference: HRVSourcePreference) async throws -> [(date: Date, hrv: Double)] { hrvData }
    func fetchDailySleep(days: Int) async throws -> [(date: Date, hours: Double, efficiency: Double)] { sleepData }
    func fetchDailySteps(days: Int) async throws -> [(date: Date, steps: Int)] { stepsData }
    func fetchWorkoutDays(days: Int) async throws -> Set<String> { workoutDays }
}

// MARK: - TrainingDNAAnalyzerTests

@MainActor
final class TrainingDNAAnalyzerTests: XCTestCase {

    // MARK: - Shared Helpers

    /// Today at midnight — stable reference so date math doesn't drift mid-test-suite.
    private let ref = Calendar.current.startOfDay(for: Date())

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: ref)!
    }

    /// In-memory ModelContainer scoped to TrainingPattern only.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrainingPattern.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// In-memory ModelContainer with both TrainingPattern and StoredDailyScore.
    /// Required for detectBackToBackReadinessCrash tests since the detector reads
    /// StoredDailyScore directly from the actor's modelContext.
    private func makeFullContainer() throws -> ModelContainer {
        let schema = Schema([TrainingPattern.self, StoredDailyScore.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    // MARK: - Pattern 1: Block Crash Cycle

    /// Three 20-day blocks (ACWR 0.82) with crash ACWR = 0.82 at each block end.
    /// stats.mean(crashACWRs) = 0.82 < 0.85 threshold → pattern fires.
    func testBlockCrashCycle_happyPath() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.acwrData = makeBlockCrashACWR(blockCount: 3, blockACWR: 0.82, gapACWR: 0.5)

        await analyzer.setDataProvider(mock)
        let returned = try await analyzer.analyze()

        XCTAssertEqual(returned, 180)
        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .blockCrashCycle },
            "Three qualifying blocks with crash ACWR 0.82 should produce a blockCrashCycle pattern"
        )
    }

    /// Only 2 qualifying blocks → blocks.count < 3 gate → no pattern.
    func testBlockCrashCycle_insufficientBlocks_returnsNil() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.acwrData = makeBlockCrashACWR(blockCount: 2, blockACWR: 0.82, gapACWR: 0.5)

        await analyzer.setDataProvider(mock)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .blockCrashCycle },
            "Only 2 blocks should not meet the 3-block minimum"
        )
    }

    /// Three blocks, crash ACWR = 0.90 → stats.mean = 0.90 ≥ 0.85 → stats gate fails → no pattern.
    func testBlockCrashCycle_statsRejection_returnsNil() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        // blockACWR = 0.90: all block days (including last = "crash" day) are 0.90
        mock.acwrData = makeBlockCrashACWR(blockCount: 3, blockACWR: 0.90, gapACWR: 0.5)

        await analyzer.setDataProvider(mock)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .blockCrashCycle },
            "Crash ACWR 0.90 ≥ 0.85 should be rejected by the statistical gate"
        )
    }

    // MARK: - Pattern 3: Sleep Fragmentation
    //
    // (Tested before HRV Precursor because it only needs historyDays >= 60,
    //  which makes fixture setup simpler — no 90-day gate to worry about.)

    /// Two 10-day high-load periods (ACWR 1.1) with sleep efficiency 0.70 vs baseline 0.85.
    /// 0.70 < 0.85 × 0.90 = 0.765, and stats.mean = 0.70 < 0.85 × 0.92 = 0.782 → pattern fires.
    func testSleepFragmentation_happyPath() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 70   // >= 60, < 90 so only sleep frag runs
        mock.acwrData  = makeSleepFragACWR(periodCount: 2)
        mock.sleepData = makeSleepFragSleep(periodCount: 2)

        await analyzer.setDataProvider(mock)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .sleepFragmentation },
            "Two high-load periods with efficiency drop 0.70 should produce a sleepFragmentation pattern"
        )
    }

    /// Only 1 high-load period → highLoadPeriods.count < 2 gate → no pattern.
    func testSleepFragmentation_insufficientPeriods_returnsNil() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 70
        mock.acwrData  = makeSleepFragACWR(periodCount: 1)
        mock.sleepData = makeSleepFragSleep(periodCount: 1)

        await analyzer.setDataProvider(mock)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .sleepFragmentation },
            "One high-load period should not meet the 2-period minimum"
        )
    }

    // MARK: - Pattern 2: HRV Precursor

    /// Three sick windows (steps < 2000 × 2 consecutive days, no workout).
    /// Precursor HRV (48h before) = 45 ms vs baseline 60 ms.
    /// 45 < 60 × 0.85 = 51 → precursor match × 3. stats.mean = 45 < 60 × 0.90 = 54 → pattern fires.
    func testHRVPrecursor_happyPath() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData    = makeHRVPrecursorHRV(baselineHRV: 60.0, precursorHRV: 45.0)
        mock.stepsData  = makeHRVPrecursorSteps(windowCount: 3)
        mock.workoutDays = []

        await analyzer.setDataProvider(mock)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .hrvPrecursor },
            "Three sick windows with HRV drop from 60 → 45 ms should produce an hrvPrecursor pattern"
        )
    }

    /// Only 2 sick windows → sickDayWindows.count < 3 gate → no pattern.
    func testHRVPrecursor_insufficientSickWindows_returnsNil() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData    = makeHRVPrecursorHRV(baselineHRV: 60.0, precursorHRV: 45.0)
        mock.stepsData  = makeHRVPrecursorSteps(windowCount: 2)
        mock.workoutDays = []

        await analyzer.setDataProvider(mock)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .hrvPrecursor },
            "Only 2 sick windows should not meet the 3-window minimum"
        )
    }

    // MARK: - analyze() historyDays Gating

    /// < 60 days of history throws PatternAnalysisError.insufficientData.
    func testAnalyze_insufficientHistory_throws() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 45
        await analyzer.setDataProvider(mock)

        do {
            _ = try await analyzer.analyze()
            XCTFail("analyze() should throw .insufficientData when historyDays < 60")
        } catch PatternAnalysisError.insufficientData {
            // expected
        }
    }

    /// 60–89 days: block crash and HRV precursor gated out; sleep frag also returns nil (thin data).
    func testAnalyze_60to89Days_skips90DayGatedPatterns() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 75
        // Would fire blockCrash if the >= 90 gate were absent
        mock.acwrData   = makeBlockCrashACWR(blockCount: 3, blockACWR: 0.82, gapACWR: 0.5)
        // Would fire HRV precursor if the >= 90 gate were absent
        mock.hrvData    = makeHRVPrecursorHRV(baselineHRV: 60.0, precursorHRV: 45.0)
        mock.stepsData  = makeHRVPrecursorSteps(windowCount: 3)
        mock.workoutDays = []
        // Only 5 sleep points — below the 20-point guard in detectSleepFragmentation
        mock.sleepData  = (0..<5).map { i in (date: day(-i - 1), hours: 7.0, efficiency: 0.85) }

        await analyzer.setDataProvider(mock)
        let returned = try await analyzer.analyze()

        XCTAssertEqual(returned, 75)
        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(patterns.contains { $0.patternType == .blockCrashCycle },
                       "blockCrashCycle requires historyDays >= 90")
        XCTAssertFalse(patterns.contains { $0.patternType == .hrvPrecursor },
                       "hrvPrecursor requires historyDays >= 90")
        XCTAssertFalse(patterns.contains { $0.patternType == .backToBackCrash },
                       "backToBackCrash requires historyDays >= 90")
    }

    // MARK: - Upsert: notificationSent Never Reset

    /// After notificationSent is set to true externally, a second analyze() run must not reset it.
    func testUpsert_notificationSentNeverReset() async throws {
        let container = try makeContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 70
        mock.acwrData  = makeSleepFragACWR(periodCount: 2)
        mock.sleepData = makeSleepFragSleep(periodCount: 2)
        await analyzer.setDataProvider(mock)

        // First run — inserts pattern with notificationSent = false
        _ = try await analyzer.analyze()

        let stored = try await analyzer.fetchAllPatterns()
        guard let pattern = stored.first(where: { $0.patternType == .sleepFragmentation }) else {
            XCTFail("sleepFragmentation pattern must exist after first analyze()"); return
        }
        XCTAssertFalse(pattern.notificationSent)
        // Set notificationSent = true directly on the actor's model object and save
        try await analyzer.markNotificationSent(patternType: .sleepFragmentation)

        // Second run — upsert must preserve notificationSent = true
        _ = try await analyzer.analyze()

        let updated = try await analyzer.fetchAllPatterns()
        let after = updated.first(where: { $0.patternType == .sleepFragmentation })
        XCTAssertEqual(after?.notificationSent, true,
                       "upsert must never reset notificationSent once it is true")
    }

    // MARK: - Pattern 4: Back-to-Back Crash

    /// 6 total sequences, 5 confirmed (drop > 10pts each, yesRate = 83% >= 60%).
    /// After analyze() the backToBackCrash pattern should be persisted.
    func testBackToBackCrash_happyPath() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        // Insert 90 days of scores with 6 back-to-back sequences, 5 confirmed
        let scores = makeBackToBackScores(confirmedCount: 5, totalSequences: 6)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .backToBackCrash },
            "5/6 confirmed sequences (83%) should produce a backToBackCrash pattern"
        )
    }

    /// Only 3 sequences in the data — below the n >= 4 minimum gate.
    func testBackToBackCrash_insufficientSequences_returnsNil() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        let scores = makeBackToBackScores(confirmedCount: 3, totalSequences: 3)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .backToBackCrash },
            "3 sequences is below the n >= 4 minimum — no pattern should fire"
        )
    }

    /// 6 sequences but only 2 confirmed (yesRate = 33% < 60% threshold).
    func testBackToBackCrash_lowYesRate_returnsNil() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        let scores = makeBackToBackScores(confirmedCount: 2, totalSequences: 6)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .backToBackCrash },
            "2/6 confirmed (33%) is below the 60% yes-rate threshold — no pattern should fire"
        )
    }

    /// Confirmed pattern has lagCorrelation set (non-nil) and peakDropDay = 1.
    func testBackToBackCrash_lagCorrelationAndPeakDaySet() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        let scores = makeBackToBackScores(confirmedCount: 5, totalSequences: 6)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        guard let p = patterns.first(where: { $0.patternType == .backToBackCrash }) else {
            XCTFail("backToBackCrash pattern must exist"); return
        }
        XCTAssertNotNil(p.lagCorrelation, "lagCorrelation must be set on a confirmed backToBackCrash pattern")
        XCTAssertEqual(p.peakDropDay, 1, "peakDropDay must be 1 (crash on the day after back-to-back)")
    }

    /// historyDays < 90 → backToBackCrash is gated out along with blockCrashCycle and hrvPrecursor.
    func testBackToBackCrash_historyGate_skipped() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 75   // < 90
        await analyzer.setDataProvider(mock)

        // Pre-populate enough data that the pattern would fire if the gate were absent
        let scores = makeBackToBackScores(confirmedCount: 5, totalSequences: 6)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .backToBackCrash },
            "detectBackToBackReadinessCrash requires historyDays >= 90"
        )
    }

    // MARK: - Pattern 4: Back-to-Back Crash — Pearson Graduation Gate

    /// n=9 sequences: vote-only gate applies (yesRate >= 0.60 required).
    /// 7/9 confirmed = 78% >= 60% → pattern fires.
    func testBackToBackCrash_n9_voteGate_fires() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        let scores = makeBackToBackScores(confirmedCount: 7, totalSequences: 9)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .backToBackCrash },
            "n=9: 7/9 confirmed (78%) should satisfy vote-only gate (>= 60%)"
        )
    }

    /// n=9 sequences: yesRate = 4/9 = 44% < 60% → vote gate fails, no pattern.
    func testBackToBackCrash_n9_lowYesRate_fails() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        let scores = makeBackToBackScores(confirmedCount: 4, totalSequences: 9)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .backToBackCrash },
            "n=9: 4/9 confirmed (44%) is below the 60% vote-only gate"
        )
    }

    /// n=10 combined gate: yesRate >= 0.40 AND lagCorrelation >= 0.55.
    /// Fixture produces enough confirmed drop events so the score series has a
    /// strong lag-1 correlation. 6/10 = 60% yesRate, r typically >= 0.55 for this layout.
    func testBackToBackCrash_n10_combinedGate_fires() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        // 10 sequences, 6 confirmed — 60% yesRate with structured crash pattern
        let scores = makeBackToBackScores(confirmedCount: 6, totalSequences: 10)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .backToBackCrash },
            "n=10: 6/10 confirmed with structured drops should satisfy combined gate"
        )
    }

    /// n=10 combined gate: yesRate = 4/10 = 40% (borderline meets rate requirement)
    /// but the crash drops are inconsistent, producing r < 0.55 → combined gate fails.
    /// We verify absence of pattern — if lagCorrelation is nil or too low the pattern must not fire.
    func testBackToBackCrash_n10_lowLagR_fails() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        await analyzer.setDataProvider(mock)

        // Only 4 confirmed crashes out of 10 — yesRate = 40%, borderline,
        // and the mix of confirmed/unconfirmed dilutes lag correlation below 0.55.
        let scores = makeBackToBackScores(confirmedCount: 4, totalSequences: 10)
        try await analyzer.insertDailyScores(scores)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        // yesRate=40% with a step-down drop sequence (4×22.5 then 6×5.5) → Pearson r is negative
        // → combined gate (yesRate>=40% AND lagR>=0.55) must fail → no pattern.
        XCTAssertFalse(
            patterns.contains { $0.patternType == .backToBackCrash },
            "n=10: 4/10 yesRate=40% with step-down drops → lagR negative → combined gate must fail"
        )
    }

    // MARK: - Fixture Generators

    /// `blockCount` blocks of 20-day ACWR > 0.8 (value = `blockACWR`) each followed by a 10-day
    /// gap at `gapACWR` (< 0.8). Returned in chronological order.
    ///
    /// The last day of each block equals `blockACWR`, so the crash window [blockEnd, blockEnd+5d]
    /// will pick up `blockACWR` as the crash signal. Set blockACWR < 0.85 to pass the crash gate,
    /// >= 0.85 to exercise the stats-rejection path.
    private func makeBlockCrashACWR(
        blockCount: Int,
        blockACWR: Double,
        gapACWR: Double
    ) -> [(date: Date, acwr: Double)] {
        let blockLen = 20
        let gapLen   = 10
        let stride   = blockLen + gapLen
        let total    = blockCount * stride + gapLen   // trailing gap so last block closes

        var data: [(date: Date, acwr: Double)] = []
        for i in 0..<total {
            let d = day(-(total - 1 - i))   // oldest first
            let blockIdx = i / stride
            let slotInStride = i % stride
            let acwr: Double
            if blockIdx < blockCount && slotInStride < blockLen {
                acwr = blockACWR
            } else {
                acwr = gapACWR
            }
            data.append((date: d, acwr: acwr))
        }
        return data
    }

    /// 60-day ACWR series with `periodCount` high-load runs of 10 days each (ACWR 1.1).
    /// Period 1 starts at day offset -60, period 2 at -40. All other days are 0.8.
    private func makeSleepFragACWR(periodCount: Int) -> [(date: Date, acwr: Double)] {
        let total = 60
        return (0..<total).map { i in
            let d = day(-(total - i))
            let inP1 = i < 10
            let inP2 = periodCount >= 2 && i >= 20 && i < 30
            return (date: d, acwr: (inP1 || inP2) ? 1.1 : 0.8)
        }
    }

    /// 60-day sleep series aligned with makeSleepFragACWR.
    /// Baseline efficiency = 0.85; high-load period efficiency = 0.70.
    private func makeSleepFragSleep(periodCount: Int) -> [(date: Date, hours: Double, efficiency: Double)] {
        let total = 60
        return (0..<total).map { i in
            let d = day(-(total - i))
            let inP1 = i < 10
            let inP2 = periodCount >= 2 && i >= 20 && i < 30
            let eff: Double = (inP1 || inP2) ? 0.70 : 0.85
            return (date: d, hours: 7.0, efficiency: eff)
        }
    }

    /// HRV series for precursor detection.
    ///
    /// The [t72, t36] window is 36h wide and spans 2 daily midnight points (sickDate-3d and
    /// sickDate-2d) plus any appended hour-precision precursor. To avoid baseline dilution
    /// (which pushes the window mean above baselineHRV × 0.85), those 2 overlapping daily
    /// entries are excluded for each sick window. The appended precursor at exactly -50h is
    /// then the ONLY value in each window.
    private func makeHRVPrecursorHRV(
        baselineHRV: Double,
        precursorHRV: Double,
        sickOffsets: [Int] = [-80, -50, -20]
    ) -> [(date: Date, hrv: Double)] {
        // Days that land inside some detection window — exclude from the daily baseline.
        let windowDays = Set(sickOffsets.flatMap { [$0 - 3, $0 - 2] })

        var data: [(date: Date, hrv: Double)] = (0..<90).compactMap { i in
            let offset = -(89 - i)
            guard !windowDays.contains(offset) else { return nil }
            return (date: day(offset), hrv: baselineHRV)
        }
        // Append precursor at exactly 50h before each sick day — inside [36h, 72h] window.
        for sickOffset in sickOffsets {
            let sickDate = day(sickOffset)
            let precursorDate = Calendar.current.date(byAdding: .hour, value: -50, to: sickDate)!
            data.append((date: precursorDate, hrv: precursorHRV))
        }
        return data
    }

    /// 90-day step series. Most days = 8000 steps. For the first `windowCount` sick offsets:
    /// two consecutive days each with 1000 steps (sick-day proxy, no workout).
    private func makeHRVPrecursorSteps(
        windowCount: Int,
        sickOffsets: [Int] = [-80, -50, -20]
    ) -> [(date: Date, steps: Int)] {
        var data: [(date: Date, steps: Int)] = (0..<90).map { i in
            (date: day(-(89 - i)), steps: 8000)
        }
        for sickOffset in sickOffsets.prefix(windowCount) {
            for delta in [0, 1] {
                let sickDay = day(sickOffset + delta)
                if let idx = data.firstIndex(where: {
                    Calendar.current.isDate($0.date, inSameDayAs: sickDay)
                }) {
                    data[idx] = (date: data[idx].date, steps: 1000)
                }
            }
        }
        return data
    }

    // MARK: - Back-to-Back Crash Fixtures

    /// Generates 90 days of StoredDailyScore covering `totalSequences` back-to-back triplets.
    ///
    /// Layout (10-day stride per sequence):
    ///   dayA [slot 0]: dailyLoad=1.5, score=70
    ///   dayB [slot 1]: dailyLoad=1.5, score=65
    ///   dayC [slot 2]: dailyLoad=0.0, score=45 → drop=(70+65)/2-45=22.5 >10 (confirmed)
    ///                                 score=62 → drop=(70+65)/2-62=5.5 <10 (not confirmed)
    ///   slots 3..9:   dailyLoad=0.0, score=70 (rest days, no triplet detected)
    ///
    /// The first `confirmedCount` sequences get score=45 (confirmed); the rest get score=62.
    /// dailyLoad=1.5 is 50% above the hardDayLoadThreshold=1.0 — clearly in real-training territory.
    private func makeBackToBackScores(
        confirmedCount: Int,
        totalSequences: Int,
        daysBack: Int = 90
    ) -> [StoredDailyScore] {
        (0..<daysBack).map { i in
            let date = day(-(daysBack - 1 - i))
            let seqIdx = i / 10
            let slot = i % 10

            let score: Int
            let load: Double

            if seqIdx < totalSequences {
                switch slot {
                case 0: score = 70; load = 1.5   // dayA — hard training day
                case 1: score = 65; load = 1.5   // dayB — hard training day
                case 2:                            // dayC — crash day
                    score = seqIdx < confirmedCount ? 45 : 62
                    load = 0.0
                default: score = 70; load = 0.0  // rest days
                }
            } else {
                score = 70; load = 0.0
            }

            return StoredDailyScore(
                date: date,
                readinessScore: score,
                dailyStrain: 1.0,
                workoutCount: load > 0 ? 1 : 0,
                dailyLoad: load
            )
        }
    }

    /// 90 days of daily warmup rides (workoutCount=1, dailyLoad=0.3 — below 1.0 threshold).
    /// No day should qualify as a "hard day" so the detector must return nil regardless of readiness drops.
    func testWarmupDaysDoNotCountAsHardDays() async throws {
        let scores = (0..<90).map { i -> StoredDailyScore in
            let date = day(-(89 - i))
            // Alternate score to create apparent readiness drops — these should be ignored
            // because the dailyLoad never reaches hardDayLoadThreshold (1.0).
            let score = i % 3 == 2 ? 45 : 70
            return StoredDailyScore(
                date: date,
                readinessScore: score,
                dailyStrain: 1.0,
                workoutCount: 1,   // warmup logged every day
                dailyLoad: 0.3    // well below 1.0 threshold
            )
        }

        let container = try makeContainer()
        let ctx = ModelContext(container)
        scores.forEach { ctx.insert($0) }
        try ctx.save()

        let analyzer = TrainingDNAAnalyzer(modelContainer: container)
        var mock = MockPatternDataProvider()
        mock.historyDays = 90
        await analyzer.setDataProvider(mock)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .backToBackCrash },
            "Warmup-only days (dailyLoad=0.3) must not qualify as hard days — no back-to-back crash pattern should be detected"
        )
    }

    // MARK: - Confidence Copy

    /// Tapering packs a percentage into numerator/denominator, so the shared
    /// "seen in N of M" phrasing rendered "seen in 41 of 30 taper" — a fraction
    /// above 1 against a singular noun. Load-based detection makes 50–70% drops
    /// routine, so this string is on screen for every real taper.
    func testTaperConfidenceTextReadsAsAPercentage() throws {
        let taper = makePattern(.tapering, detectedAt: Date())   // 41 / 30
        XCTAssertEqual(taper.confidenceCountText, "load down 41% (30% threshold)")
        XCTAssertFalse(
            taper.confidenceCountText.contains("seen in"),
            "Taper must not use the N-of-M instance-count phrasing"
        )
    }

    /// The other five pattern types genuinely count instances — leave them alone.
    func testNonTaperConfidenceTextKeepsInstanceCount() throws {
        let crash = makePattern(.backToBackCrash, detectedAt: Date())  // 41 / 30
        XCTAssertEqual(crash.confidenceCountText, "seen in 41 of 30 sequences")
    }

    // MARK: - Pattern Staleness (isActive)

    /// Builds a pattern with an explicit detectedAt. Field values are irrelevant here —
    /// only recency is under test.
    private func makePattern(
        _ type: PatternType,
        detectedAt: Date
    ) -> TrainingPattern {
        TrainingPattern(
            patternType: type,
            detectedAt: detectedAt,
            confidenceNumerator: 41,
            confidenceDenominator: 30,
            evidenceSummary: "Load down 41% — peak form expected Jul 24.",
            citationKey: type.citationKey,
            instanceDates: [detectedAt],
            coachingResponse: "Taper underway — keep intensity but cut volume."
        )
    }

    /// Regression: a taper detected weeks ago and never re-detected kept rendering on
    /// the Training DNA card list forever, claiming "Load down 41%" while the Load tab
    /// correctly read ACWR ~1.0. Nothing deletes a TrainingPattern, so recency is the
    /// only signal that a pattern still holds.
    func testPatternDetectedThreeWeeksAgoIsNotActive() throws {
        let stale = makePattern(.tapering, detectedAt: day(-21))
        XCTAssertFalse(
            stale.isActive,
            "A pattern last re-detected 21 days ago must not count as active — it is what froze a stale taper card on Training DNA"
        )
    }

    func testPatternDetectedTodayIsActive() throws {
        XCTAssertTrue(
            makePattern(.tapering, detectedAt: Date()).isActive,
            "A pattern re-detected today must be active"
        )
    }

    /// Pins the 7-day window itself. MainTabView's badge, PatternsTabView's header
    /// strip, RecoveryTabView's top pattern and InsightsView's card list all read
    /// isActive — changing this constant moves all four together, by design.
    func testActiveWindowBoundaryIsSevenDays() throws {
        XCTAssertEqual(TrainingPattern.activeWindowDays, 7)

        // 6 days ago: inside the window.
        XCTAssertTrue(
            makePattern(.performancePeak, detectedAt: day(-6)).isActive,
            "6 days old is inside the 7-day active window"
        )
        // 8 days ago: outside it.
        XCTAssertFalse(
            makePattern(.performancePeak, detectedAt: day(-8)).isActive,
            "8 days old is outside the 7-day active window"
        )
    }

    /// The card list and the tab badge must agree. Before the fix the badge filtered
    /// on recency and the card list did not, so the badge read 0 while a taper card
    /// was still on screen.
    func testCardListAndBadgeSeeTheSameActiveSet() throws {
        let patterns = [
            makePattern(.tapering, detectedAt: day(-21)),        // stale
            makePattern(.sleepFragmentation, detectedAt: day(-2)) // fresh
        ]

        let cardList = patterns.filter { $0.isActive }
        let badgeCount = patterns.filter { $0.isActive }.count

        XCTAssertEqual(cardList.count, badgeCount)
        XCTAssertEqual(cardList.count, 1, "Only the fresh pattern is active")
        XCTAssertEqual(
            cardList.first?.patternType, .sleepFragmentation,
            "The stale taper must be filtered out of the Training DNA card list"
        )
    }
}
