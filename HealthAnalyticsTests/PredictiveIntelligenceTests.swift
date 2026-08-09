//
//  PredictiveIntelligenceTests.swift
//  HealthAnalyticsTests
//
//  Phase 3 — Predictive Intelligence
//  Tests for Parts 2-4 and StatisticalValidator.linearRegression.
//  All fixtures are self-contained; no shared helpers with other test files.
//
//  Coverage:
//    - StatisticalValidator.linearRegression: happy path, zero slope, edge cases
//    - detectPerformancePeak: confirmed, boundary (p=0.80), below gate, no HRV data, ACWR break
//    - compute7DayForecast: < 14 entries, 7-day output, widening bands, coaching labels (4 tiers)
//    - detectTaperUnderway: confirmed, < 30% drop, negative HRV slope, < 28 scores, peakDate

import XCTest
import SwiftData
import HealthKit
@testable import HealthAnalytics

@MainActor
final class PredictiveIntelligenceTests: XCTestCase {

    override func setUp() async throws {
        ReadinessRepository.shared.resetForTesting()
    }

    // MARK: - Shared Helpers

    private let ref = Calendar.current.startOfDay(for: Date())

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: ref)!
    }

    /// In-memory container with TrainingPattern + StoredDailyScore.
    private func makeFullContainer() throws -> ModelContainer {
        let schema = Schema([TrainingPattern.self, StoredDailyScore.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    // MARK: - StatisticalValidator.linearRegression

    /// y = 2x + 1 — canonical linear case.
    func testLinearRegression_happyPath() {
        let result = StatisticalValidator.linearRegression(
            x: [0.0, 1.0, 2.0, 3.0, 4.0],
            y: [1.0, 3.0, 5.0, 7.0, 9.0]
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.slope,     2.0, accuracy: 0.001)
        XCTAssertEqual(result!.intercept, 1.0, accuracy: 0.001)
    }

    /// Constant series — slope must be exactly zero.
    func testLinearRegression_zeroSlope() {
        let result = StatisticalValidator.linearRegression(
            x: [0.0, 1.0, 2.0],
            y: [5.0, 5.0, 5.0]
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.slope,     0.0, accuracy: 0.001)
        XCTAssertEqual(result!.intercept, 5.0, accuracy: 0.001)
    }

    func testLinearRegression_empty_returnsNil() {
        XCTAssertNil(StatisticalValidator.linearRegression(x: [], y: []))
    }

    func testLinearRegression_singlePoint_returnsNil() {
        XCTAssertNil(StatisticalValidator.linearRegression(x: [0.0], y: [5.0]))
    }

    func testLinearRegression_countMismatch_returnsNil() {
        XCTAssertNil(StatisticalValidator.linearRegression(x: [0.0, 1.0], y: [0.0]))
    }

    // MARK: - Part 2: detectPerformancePeak
    //
    // Fixture geometry:
    //   makeHRVPeakData(highDays: N, totalDays: 90):
    //     - First (90-N) days at hrv=40 (low baseline)
    //     - Last N days at hrv=80 (high)
    //     - When N >= 18: p80idx=72 lands in the 80-range → p80threshold=80.
    //       Only high days satisfy, giving HRV streak = N.
    //   makeACWRStreakScores(streakLen: K):
    //     - Last K days at dailyStrain=1.0 (in [0.8, 1.3] sweet spot)
    //     - Older days at dailyStrain=0.5 (breaks streak)
    //
    // Probability formula: min(1,hrv/7)*0.60 + min(1,acwr/10)*0.40; gate >= 0.80.

    /// HRV streak = 21, ACWR streak = 10 → probability = 1.00 ≥ 0.80 → confirmed.
    func testPerformancePeak_fullStreak_confirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeHRVPeakData(highDays: 21)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeACWRStreakScores(streakLen: 10))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .performancePeak },
            "21-day HRV streak + 10-day ACWR streak → probability 1.00 should confirm performancePeak"
        )
    }

    /// HRV streak = 18, ACWR streak = 5 → probability = 0.60 + 0.20 = 0.80 → boundary confirmed.
    func testPerformancePeak_boundaryProbability_confirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeHRVPeakData(highDays: 18)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeACWRStreakScores(streakLen: 5))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .performancePeak },
            "Probability exactly 0.80 (boundary) must confirm performancePeak"
        )
    }

    /// HRV streak = 18, ACWR streak = 4 → probability = 0.60 + 0.16 = 0.76 < 0.80 → NOT confirmed.
    func testPerformancePeak_belowProbabilityGate_notConfirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeHRVPeakData(highDays: 18)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeACWRStreakScores(streakLen: 4))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .performancePeak },
            "Probability 0.76 must be below 0.80 gate — no performancePeak"
        )
    }

    /// < 7 HRV samples → guard at top of detectPerformancePeak → no pattern.
    func testPerformancePeak_insufficientHRVSamples_returnsNil() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = [(date: day(-1), hrv: 80.0)]  // only 1 sample
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeACWRStreakScores(streakLen: 10))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .performancePeak },
            "Fewer than 7 HRV samples should prevent performancePeak detection"
        )
    }

    /// All ACWR values outside [0.8, 1.3] → streak = 0 → probability = 0.60 < 0.80 → NOT confirmed.
    func testPerformancePeak_noACWRStreak_notConfirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeHRVPeakData(highDays: 21)
        await analyzer.setDataProvider(mock)

        // All strain values outside sweet spot — ACWR streak = 0
        let scores = (0..<90).map { i in
            StoredDailyScore(date: day(-(89 - i)), readinessScore: 70, dailyStrain: 0.5, workoutCount: 0)
        }
        try await analyzer.insertDailyScores(scores)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .performancePeak },
            "ACWR streak = 0 → probability = 0.60 — below 0.80 gate"
        )
    }

    // MARK: - Part 3: compute7DayForecast
    //
    // Calls ReadinessRepository.shared.compute7DayForecast(modelContext:) directly.
    // currentReadiness is nil in test context → ACWR modifier is neutral (skipped).

    /// Fewer than 14 StoredDailyScore records → must return nil.
    func testForecast_insufficientData_returnsNil() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        for i in 0..<13 {
            ctx.insert(StoredDailyScore(date: day(-i), readinessScore: 70, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)
        XCTAssertNil(result, "Fewer than 14 entries must return nil")
    }

    /// Exactly 14 entries → 7 forecast days returned.
    func testForecast_14Entries_returns7Days() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 75, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.count, 7, "Forecast must return exactly 7 days")
    }

    /// Day 7 confidence band must be wider than Day 1 (σ = min(15, baselineσ × √d)).
    func testForecast_bandWidensOverTime() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        // Varying scores to produce non-zero baselineSigma
        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 60 + i * 2, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        let band1 = result[0].confidenceHigh - result[0].confidenceLow
        let band7 = result[6].confidenceHigh - result[6].confidenceLow
        XCTAssertGreaterThan(band7, band1, "Confidence band must widen across 7 days (σ × √d)")
    }

    /// Flat readiness history (slope ≈ 0) → all predictions near 75.
    func testForecast_flatTrend_predictionsNearBaseline() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 75, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        for day in result {
            XCTAssertEqual(Double(day.predictedReadiness), 75.0, accuracy: 5.0,
                           "Flat trend must project near baseline 75")
        }
    }

    /// score ≥ 80 → coaching = "Hard effort OK"
    func testForecast_coaching_hardEffortAbove80() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 85, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        XCTAssertEqual(result[0].coaching, "Hard effort OK",
                      "Score ≥ 80 must produce 'Hard effort OK' on day 1")
    }

    /// score in [70, 79] → coaching = "Moderate training"
    func testForecast_coaching_moderateAt70to79() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 74, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        XCTAssertEqual(result[0].coaching, "Moderate training",
                      "Score in [70,79] must produce 'Moderate training' on day 1")
    }

    /// score in [60, 69] → coaching = "Easy only"
    func testForecast_coaching_easyAt60to69() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 64, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        XCTAssertEqual(result[0].coaching, "Easy only",
                      "Score in [60,69] must produce 'Easy only' on day 1")
    }

    /// score < 60 → coaching = "Rest recommended"
    func testForecast_coaching_restBelow60() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 25, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        XCTAssertEqual(result[0].coaching, "Rest recommended",
                      "Score < 60 must produce 'Rest recommended' on day 1")
    }

    // MARK: - Part 4: detectTaperUnderway
    //
    // Fixture geometry:
    //   makeTaperScores(last7Load:prev21Load:totalDays:):
    //     90 days of scores. Last 7 days at last7Load, all earlier days at prev21Load.
    //     The detector reads scores28 (last 28 days from modelContext) and splits:
    //       last7 = suffix(7), prev21 = prefix(21).
    //     Drop formula: (prev21Mean - last7Mean) / prev21Mean. Gate: >= 0.30.
    //     Bands on dailyLoad (actual TSS/day), NOT dailyStrain (the ACWR ratio) —
    //     the fixture pins dailyStrain to a constant so a regression to it goes red.
    //   makeTaperHRVData(slope:): 7 HRV entries increasing (positive) or decreasing (negative).
    //
    // Probability formula: min(1, drop/0.30)*0.60 + (positiveSlope ? 0.40 : 0.0); gate >= 0.80.

    /// 35% load drop + positive HRV slope → probability = 1.00 ≥ 0.80 → confirmed.
    func testTaperUnderway_confirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.65, prev21Load: 1.0))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .tapering },
            "35% load drop + positive HRV slope should produce tapering pattern"
        )
    }

    /// 29% load drop → guard (drop >= 0.30) fails → no pattern.
    func testTaperUnderway_insufficientLoadDrop_notConfirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        // 29% drop: (1.0 - 0.71) / 1.0 = 0.29
        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.71, prev21Load: 1.0))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .tapering },
            "29% drop is below the 30% threshold — no tapering pattern"
        )
    }

    /// 35% drop + negative HRV slope → probability = 0.60 + 0.0 = 0.60 < 0.80 → no pattern.
    func testTaperUnderway_negativeHRVSlope_notConfirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: false)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.65, prev21Load: 1.0))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .tapering },
            "Negative HRV slope → probability = 0.60 — below 0.80 gate"
        )
    }

    /// Fewer than 28 StoredDailyScore records within the last 28 days → guard fails → no pattern.
    func testTaperUnderway_insufficientScoreCount_returnsNil() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        // Only 20 recent scores — below 28-day guard
        let scores = (0..<20).map { i in
            StoredDailyScore(date: day(-(19 - i)), readinessScore: 70, dailyStrain: 1.0, workoutCount: 1)
        }
        try await analyzer.insertDailyScores(scores)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .tapering },
            "Fewer than 28 scores must prevent taper detection"
        )
    }

    /// Confirmed taper: peakDate must be today + 14 days (Mujika & Padilla 2003).
    func testTaperUnderway_peakDate_is14DaysFromNow() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.65, prev21Load: 1.0))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        guard let p = patterns.first(where: { $0.patternType == .tapering }) else {
            XCTFail("Tapering pattern must exist for peakDate assertion"); return
        }
        let expected = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        let diff = abs(p.peakDate!.timeIntervalSince(expected))
        XCTAssertLessThan(diff, 60, "peakDate must be today + 14 days (Mujika & Padilla 2003)")
    }

    // MARK: - Part 4 (regression): taper must band on load, not the ACWR ratio

    /// Builds 90 days where actual daily load is FLAT but the ACWR ratio decays hard,
    /// which is what happens for ~28 days after any step up in training: the 28-day
    /// chronic denominator is still catching up to the 7-day acute numerator.
    ///
    /// Load is constant, so a load-based detector must stay silent. `dailyStrain` walks
    /// 2.20 → 1.00 across the 28-day window (a 41% mean drop, well past the 30% gate),
    /// so an ACWR-based detector fires. That difference is the regression.
    private func makeFlatLoadDecayingACWRScores(totalDays: Int = 90) -> [StoredDailyScore] {
        (0..<totalDays).map { i in
            let daysAgo = totalDays - 1 - i
            // Linear decay from 2.20 (28 days ago) down to 1.00 (today).
            let strain = daysAgo >= 28 ? 2.20 : 1.00 + (Double(daysAgo) / 28.0) * 1.20
            return StoredDailyScore(
                date: day(-daysAgo),
                readinessScore: 70,
                dailyStrain: strain,
                workoutCount: 1,
                dailyLoad: 1.0   // FLAT — training volume never changed
            )
        }
    }

    /// Regression: "stepped up training a month ago and held it flat" must NOT read as a taper.
    /// This is the false positive the user hit — Training DNA claimed "Taper Underway /
    /// Load down 41%" while the Load tab correctly showed ACWR ~1.0 and steady volume.
    func testTaperUnderway_flatLoadWithDecayingACWR_notConfirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)   // HRV gate satisfied
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeFlatLoadDecayingACWRScores())
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .tapering },
            "Unchanged training volume must never read as a taper — a decaying ACWR ratio is the 28-day chronic window catching up, not an unload"
        )
    }

    /// Regression: a genuine 50% volume cut must fire. The old ACWR-ratio metric moved
    /// only ~24% here and missed it entirely.
    func testTaperUnderway_genuineHalvedVolume_confirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        // 50% drop: baseline 2.0 TSS/day → 1.0 TSS/day for the last week.
        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 1.0, prev21Load: 2.0))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(
            patterns.contains { $0.patternType == .tapering },
            "Halving training volume is a real taper and must be detected"
        )
    }

    /// Regression: duplicate-day rows must not manufacture a taper.
    ///
    /// StoredDailyScore dedup is in-memory only, so the store can hold two rows for one
    /// calendar day after a race or a migration. Slicing ROWS instead of distinct days
    /// let suffix(7) span fewer than 7 days, and a double-counted rest day (dailyLoad
    /// 0.0) in the recent slice deflates the mean enough to clear the 30% gate on its
    /// own — a false taper for someone whose volume never moved.
    func testTaperUnderway_duplicateDayRows_doNotFabricateADrop() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)   // HRV gate satisfied
        await analyzer.setDataProvider(mock)

        // 90 days of perfectly flat 2.0 TSS/day — no taper anywhere in the data.
        var scores = (0..<90).map { i -> StoredDailyScore in
            StoredDailyScore(
                date: day(-(89 - i)), readinessScore: 70,
                dailyStrain: 1.0, workoutCount: 1, dailyLoad: 2.0
            )
        }
        // Three extra rows for recent days carrying 0.0 load, as a partial upsert or a
        // migration would leave behind. Row count still passes a naive `>= 28` check.
        for offset in [1, 3, 5] {
            scores.append(StoredDailyScore(
                date: day(-offset), readinessScore: 70,
                dailyStrain: 1.0, workoutCount: 0, dailyLoad: 0.0
            ))
        }
        try await analyzer.insertDailyScores(scores)
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .tapering },
            "Duplicate rows for a calendar day must be collapsed before slicing — flat 2.0 TSS/day is not a taper"
        )
    }

    /// Regression: with no training to taper from, a drop to zero must not fire.
    /// Also covers pre-migration rows where every dailyLoad defaults to 0.0.
    func testTaperUnderway_noBaselineTrainingLoad_notConfirmed() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        // Baseline 0.1/day is below taperBaselineLoadThreshold (0.25); last week is 0.
        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.0, prev21Load: 0.1))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .tapering },
            "A sedentary baseline has no training block to taper from — must not fire"
        )
    }

    // MARK: - Part 2 (extra): HRV streak broken by below-threshold entry

    /// 22 high-HRV entries total, but a below-threshold entry at day -3 breaks the trailing streak.
    /// Iteration (newest first): days 0,-1,-2 → streak=3, day -3 (hrv=40) → break.
    /// hrv streak = 3 → hrvScore = min(1, 3/7)*0.60 = 0.257; ACWR streak = 10 → acwrScore = 0.40
    /// probability = 0.66 < 0.80 → NOT confirmed.
    func testPerformancePeak_streakBrokenByLowDay_notConfirmed() async throws {
        let container = try makeFullContainer()
        let analyzer  = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180

        // Geometry (90 entries):
        //   days -89 … -23 (67 entries): hrv=40
        //   days -22 … -4  (19 entries): hrv=80  ← ensures p80threshold lands at 80
        //   day  -3         (1 entry):   hrv=40  ← breaks the trailing streak
        //   days -2,  -1, 0 (3 entries): hrv=80  ← trailing streak = 3
        // sortedHRV: 68×40, 22×80 → p80idx=72 → threshold=80
        var hrv: [(date: Date, hrv: Double)] = []
        for i in 0..<67 { hrv.append((date: day(-(89 - i)), hrv: 40.0)) }
        for i in 0..<19 { hrv.append((date: day(-(22 - i)), hrv: 80.0)) }
        hrv.append((date: day(-3), hrv: 40.0))
        for i in 0..<3  { hrv.append((date: day(-(2  - i)), hrv: 80.0)) }
        mock.hrvData = hrv
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeACWRStreakScores(streakLen: 10))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(
            patterns.contains { $0.patternType == .performancePeak },
            "HRV streak broken at day -3 → streak=3 → probability 0.66 < 0.80 — no performancePeak"
        )
    }

    // MARK: - Part 3 (extra): compute7DayForecast ACWR modifier and clamp

    /// ACWR > 1.3 → each forecast day decays by 3%×d. Day 7 must be lower than Day 1.
    func testForecast_acwrOverload_forecastDecays() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)
        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 75, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx, overrideACWR: 1.5)!
        XCTAssertLessThan(
            result[6].predictedReadiness, result[0].predictedReadiness,
            "ACWR=1.5 (overload) → 3%%/day decay → day 7 must be lower than day 1"
        )
    }

    /// ACWR < 0.8 → each forecast day improves by 2%×d. Day 7 must be higher than Day 1.
    func testForecast_acwrUnderload_forecastImproves() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)
        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 65, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx, overrideACWR: 0.6)!
        XCTAssertGreaterThan(
            result[6].predictedReadiness, result[0].predictedReadiness,
            "ACWR=0.6 (underload) → 2%%/day improvement → day 7 must be higher than day 1"
        )
    }

    /// ACWR overload on a low baseline pushes prediction below 20 → clamp floor enforced.
    /// Flat trend at 25; ACWR=2.0; day 7: 25 - 25×0.03×7 = 19.75 → clamped to 20.
    func testForecast_clampFloor_noPredictionBelow20() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)
        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 25, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx, overrideACWR: 2.0)!
        for forecastDay in result {
            XCTAssertGreaterThanOrEqual(forecastDay.predictedReadiness, 20,
                "Predicted readiness must never fall below the 20-point floor")
        }
    }

    /// ACWR underload on a high baseline pushes prediction above 100 → clamp ceiling enforced.
    /// Flat trend at 95; ACWR=0.6; day 7: 95 + 95×0.02×7 = 108.3 → clamped to 100.
    func testForecast_clampCeiling_noPredictionAbove100() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)
        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 95, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx, overrideACWR: 0.6)!
        for forecastDay in result {
            XCTAssertLessThanOrEqual(forecastDay.predictedReadiness, 100,
                "Predicted readiness must never exceed the 100-point ceiling")
        }
        XCTAssertEqual(result[6].predictedReadiness, 100,
            "Day 7 underload from a 95 baseline must hit the ceiling exactly")
    }

    /// ACWR in the sweet spot [0.8, 1.3] → homeostasis pulls an above-baseline
    /// forecast back toward 75 without overshooting below it.
    func testForecast_acwrSweetSpot_driftsToward75() throws {
        let container = try makeFullContainer()
        let ctx = ModelContext(container)
        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 85, dailyStrain: 1.0, workoutCount: 0))
        }
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx, overrideACWR: 1.0)!
        XCTAssertLessThan(result[6].predictedReadiness, result[0].predictedReadiness,
            "Sweet-spot ACWR must pull an above-baseline forecast back toward 75")
        XCTAssertGreaterThanOrEqual(result[6].predictedReadiness, 75,
            "Homeostasis pull must not overshoot below the 75 baseline within 7 days")
    }

    // MARK: - performancePeak notification dedup

    /// A performancePeak pattern with notificationSent=true must not be reset to false by a
    /// subsequent analyze() run — identical guard to the sleepFragmentation upsert test.
    func testPerformancePeak_notificationSentNeverReset() async throws {
        let container = try makeFullContainer()
        let analyzer  = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeHRVPeakData(highDays: 21)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeACWRStreakScores(streakLen: 10))

        // First run: inserts performancePeak with notificationSent = false
        _ = try await analyzer.analyze()
        let stored = try await analyzer.fetchAllPatterns()
        guard let pattern = stored.first(where: { $0.patternType == .performancePeak }) else {
            XCTFail("performancePeak must exist after first analyze()"); return
        }
        XCTAssertFalse(pattern.notificationSent, "notificationSent must start false")

        // Simulate notification dispatch marking it sent
        try await analyzer.markNotificationSent(patternType: .performancePeak)

        // Second run: upsert must preserve notificationSent = true
        _ = try await analyzer.analyze()
        let updated = try await analyzer.fetchAllPatterns()
        let after = updated.first(where: { $0.patternType == .performancePeak })
        XCTAssertEqual(after?.notificationSent, true,
                       "upsert must never reset notificationSent once it is true for performancePeak")
    }

    // MARK: - Fixture Generators

    /// 90 HRV entries. First (90 - highDays) days at hrv=40, last highDays at hrv=80.
    /// For highDays >= 18: p80 threshold lands at 80 → only the high days satisfy it,
    /// giving an HRV streak equal to exactly highDays.
    private func makeHRVPeakData(highDays: Int, totalDays: Int = 90) -> [(date: Date, hrv: Double)] {
        let lowDays = totalDays - highDays
        let low  = (0..<lowDays).map { i in (date: day(-(totalDays - 1 - i)), hrv: 40.0) }
        let high = (0..<highDays).map { i in (date: day(-(highDays - 1 - i)), hrv: 80.0) }
        return low + high
    }

    /// 90 StoredDailyScore entries. Last streakLen days at dailyStrain = 1.0 (ACWR sweet spot).
    /// Earlier days at dailyStrain = 0.5 (below sweet spot, breaks streak).
    private func makeACWRStreakScores(streakLen: Int, totalDays: Int = 90) -> [StoredDailyScore] {
        (0..<totalDays).map { i in
            let daysAgo = totalDays - 1 - i
            return StoredDailyScore(
                date: day(-daysAgo),
                readinessScore: 70,
                dailyStrain: daysAgo < streakLen ? 1.0 : 0.5,
                workoutCount: 0
            )
        }
    }

    /// 90 days of StoredDailyScore for taper detection.
    /// Last 7 days use last7Strain; all earlier days use prev21Strain.
    /// Builds taper fixtures on `dailyLoad` (actual TSS/day) — the field the detector reads.
    ///
    /// `dailyStrain` is deliberately pinned to a CONSTANT 1.0 across every day. It carries
    /// no drop at all, so if `detectTaperUnderway` is ever reconnected to it the taper tests
    /// go red instead of passing by coincidence.
    private func makeTaperScores(
        last7Load: Double,
        prev21Load: Double,
        totalDays: Int = 90
    ) -> [StoredDailyScore] {
        (0..<totalDays).map { i in
            let daysAgo = totalDays - 1 - i
            return StoredDailyScore(
                date: day(-daysAgo),
                readinessScore: 70,
                dailyStrain: 1.0,   // constant on purpose — see note above
                workoutCount: 1,
                dailyLoad: daysAgo < 7 ? last7Load : prev21Load
            )
        }
    }

    // MARK: - Forecast load ceiling

    /// Container that also holds workouts, so the forecast can compute a real
    /// projected ACWR. `makeFullContainer` deliberately omits them — the earlier
    /// forecast tests exercise the pure-recovery path.
    private func makeContainerWithWorkouts() throws -> ModelContainer {
        let schema = Schema([
            TrainingPattern.self, StoredDailyScore.self,
            StoredWorkout.self, StoredFTPSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// 21 days of 1h/day cycling ending a week ago, then `acuteHours`/day for the
    /// last 7 days.
    ///
    /// Note the horizon: forecast day 1 is *tomorrow*, and its window closes at the
    /// end of tomorrow — by which point the oldest acute day has already rolled out.
    /// acuteHours = 3.0 lands ACWR ≈ 1.8 there (2.0 only reaches ≈ 1.45).
    private func insertRampWorkouts(_ ctx: ModelContext, acuteHours: Double) {
        for offset in 8...28 {
            ctx.insert(StoredWorkout(
                id: "base-\(offset)", type: .cycling,
                startDate: day(-offset).addingTimeInterval(9 * 3600),
                duration: 3600, distance: nil, power: nil, energy: nil, hr: nil,
                source: "test"
            ))
        }
        for offset in 0...6 {
            ctx.insert(StoredWorkout(
                id: "acute-\(offset)", type: .cycling,
                startDate: day(-offset).addingTimeInterval(9 * 3600),
                duration: acuteHours * 3600, distance: nil, power: nil, energy: nil, hr: nil,
                source: "test"
            ))
        }
    }

    /// A well-recovered athlete deep in an overload ramp must not be told to go
    /// hard tomorrow. Recovery alone said "Hard effort OK" while the Load tab was
    /// telling the same user to take rest days.
    func testForecast_overloadCapsNearTermLabel() throws {
        let container = try makeContainerWithWorkouts()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 88, dailyStrain: 1.0, workoutCount: 1))
        }
        insertRampWorkouts(ctx, acuteHours: 3.0)
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        XCTAssertGreaterThanOrEqual(result[0].predictedReadiness, 80,
            "Fixture must keep recovery in the 'hard effort' band, or the test proves nothing")
        XCTAssertEqual(result[0].coaching, "Easy only",
            "ACWR > 1.5 must cap tomorrow's label regardless of how recovered the athlete is")
    }

    /// The ceiling relaxes across the horizon: the forecast assumes no further
    /// workouts, so the 7-day acute window empties and the ramp clears.
    func testForecast_loadCeilingRelaxesAcrossHorizon() throws {
        let container = try makeContainerWithWorkouts()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 88, dailyStrain: 1.0, workoutCount: 1))
        }
        insertRampWorkouts(ctx, acuteHours: 3.0)
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        let restrictiveness = ["Hard effort OK": 0, "Moderate training": 1, "Easy only": 2, "Rest recommended": 3]

        XCTAssertLessThan(restrictiveness[result[6].coaching]!, restrictiveness[result[0].coaching]!,
            "Day 7 must be less restricted than day 1 — a week without training clears the acute window")
    }

    /// The load signal is a ceiling, never a floor: it must not upgrade a poor
    /// recovery day into something easier-sounding.
    func testForecast_loadCeilingNeverLoosensPoorRecovery() throws {
        let container = try makeContainerWithWorkouts()
        let ctx = ModelContext(container)

        for i in 0..<14 {
            ctx.insert(StoredDailyScore(date: day(-13 + i), readinessScore: 25, dailyStrain: 1.0, workoutCount: 0))
        }
        insertRampWorkouts(ctx, acuteHours: 3.0)
        try ctx.save()

        let result = ReadinessRepository.shared.compute7DayForecast(modelContext: ctx)!
        XCTAssertEqual(result[0].coaching, "Rest recommended",
            "A 'rest' recovery verdict must survive a load ceiling of 'easy only'")
    }

    /// 7 HRV entries spanning the last 7 days with a monotone slope.
    private func makeTaperHRVData(positive: Bool) -> [(date: Date, hrv: Double)] {
        let values: [Double] = positive
            ? [40, 42, 44, 46, 48, 50, 52]   // slope = +2 → positive ✓
            : [52, 50, 48, 46, 44, 42, 40]   // slope = -2 → negative ✗
        return values.enumerated().map { (i, hrv) in
            (date: day(-(6 - i)), hrv: hrv)
        }
    }
}
