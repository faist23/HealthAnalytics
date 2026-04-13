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
@testable import HealthAnalytics

@MainActor
final class PredictiveIntelligenceTests: XCTestCase {

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
        XCTAssertTrue(result.allSatisfy { $0.coaching == "Hard effort OK" },
                      "Score ≥ 80 must produce 'Hard effort OK'")
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
        XCTAssertTrue(result.allSatisfy { $0.coaching == "Moderate training" },
                      "Score in [70,79] must produce 'Moderate training'")
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
        XCTAssertTrue(result.allSatisfy { $0.coaching == "Easy only" },
                      "Score in [60,69] must produce 'Easy only'")
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
        XCTAssertTrue(result.allSatisfy { $0.coaching == "Rest recommended" },
                      "Score < 60 must produce 'Rest recommended'")
    }

    // MARK: - Part 4: detectTaperUnderway
    //
    // Fixture geometry:
    //   makeTaperScores(last7Strain:prev21Strain:totalDays:):
    //     90 days of scores. Last 7 days at last7Strain, all earlier days at prev21Strain.
    //     The detector reads scores28 (last 28 days from modelContext) and splits:
    //       last7 = suffix(7), prev21 = prefix(21).
    //     Drop formula: (prev21Mean - last7Mean) / prev21Mean. Gate: >= 0.30.
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

        try await analyzer.insertDailyScores(makeTaperScores(last7Strain: 0.65, prev21Strain: 1.0))
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
        try await analyzer.insertDailyScores(makeTaperScores(last7Strain: 0.71, prev21Strain: 1.0))
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

        try await analyzer.insertDailyScores(makeTaperScores(last7Strain: 0.65, prev21Strain: 1.0))
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

        try await analyzer.insertDailyScores(makeTaperScores(last7Strain: 0.65, prev21Strain: 1.0))
        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        guard let p = patterns.first(where: { $0.patternType == .tapering }) else {
            XCTFail("Tapering pattern must exist for peakDate assertion"); return
        }
        let expected = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        let diff = abs(p.peakDate!.timeIntervalSince(expected))
        XCTAssertLessThan(diff, 60, "peakDate must be today + 14 days (Mujika & Padilla 2003)")
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
    private func makeTaperScores(
        last7Strain: Double,
        prev21Strain: Double,
        totalDays: Int = 90
    ) -> [StoredDailyScore] {
        (0..<totalDays).map { i in
            let daysAgo = totalDays - 1 - i
            return StoredDailyScore(
                date: day(-daysAgo),
                readinessScore: 70,
                dailyStrain: daysAgo < 7 ? last7Strain : prev21Strain,
                workoutCount: 1
            )
        }
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
