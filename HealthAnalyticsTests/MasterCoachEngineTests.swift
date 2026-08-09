//
//  MasterCoachEngineTests.swift
//  HealthAnalyticsTests
//

import XCTest
@testable import HealthAnalytics

final class MasterCoachEngineTests: XCTestCase {

    // MARK: - Existing baseline cases (activePatterns defaults to [])

    func testMorningWorkoutFatigue() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85,
            currentScore: 42,
            nextDayForecast: "Rest recommended",
            acwr: 1.1,
            injuryRisk: .low
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("woke up primed at 85%"), "Message should acknowledge morning score: \(message)")
        XCTAssertTrue(message.contains("down to 42%"), "Message should acknowledge current score: \(message)")
        XCTAssertTrue(message.contains("take it easy"), "Message should advise rest: \(message)")
        XCTAssertTrue(message.contains("rest day tomorrow"), "Message should include forecast: \(message)")
    }

    func testHighInjuryRiskOverride() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85,
            currentScore: 85,
            nextDayForecast: "Hard effort OK",
            acwr: 1.6,
            injuryRisk: .high
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("injury risk is elevated"), "Message should warn about injury risk: \(message)")
        XCTAssertTrue(message.contains("hard effort tomorrow"), "Message should include forecast: \(message)")
    }

    func testStableReadiness() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 75,
            currentScore: 75,
            nextDayForecast: "Moderate training",
            acwr: 1.0,
            injuryRisk: .low
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("75% recovered"), "Message should acknowledge recovery level: \(message)")
        XCTAssertTrue(message.contains("expect moderate training tomorrow"), "Message should include forecast: \(message)")
    }

    // MARK: - Pattern-aware paths

    func testHRVPrecursorOverridesEverything() async {
        // HRV precursor should override even a high-readiness, low-injury-risk state
        let state = MasterCoachEngine.StateVector(
            morningScore: 90,
            currentScore: 88,
            nextDayForecast: "Hard effort OK",
            acwr: 1.0,
            injuryRisk: .low,
            activePatterns: ["hrvPrecursor"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("early warning pattern"), "HRV precursor must override positive readiness: \(message)")
        XCTAssertTrue(message.contains("prioritize sleep"), "HRV precursor must recommend sleep: \(message)")
        XCTAssertFalse(message.contains("ready for intensity"), "Should not give positive message under HRV precursor: \(message)")
    }

    func testPerformancePeakUpgradesExcellentReadiness() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 88,
            currentScore: 85,
            nextDayForecast: nil,
            acwr: 1.1,
            injuryRisk: .low,
            activePatterns: ["performancePeak"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("peak form window"), "Peak pattern should upgrade excellent readiness message: \(message)")
        XCTAssertTrue(message.contains("race or benchmark"), "Peak message should suggest race/benchmark: \(message)")
    }

    func testTaperingUpgradesExcellentReadiness() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 82,
            currentScore: 81,
            nextDayForecast: nil,
            acwr: 0.75,
            injuryRisk: .low,
            activePatterns: ["tapering"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("tapering"), "Taper pattern should be called out: \(message)")
        XCTAssertTrue(
            message.contains("training volume is down"),
            "Taper message should lead with the measurement: \(message)"
        )
        // Previously asserted "peak window" unconditionally. The detector cannot tell a
        // chosen taper from injury or illness, so a peak-form promise is only safe when
        // it is hedged on the reduction having been planned.
        XCTAssertTrue(
            message.contains("If you're tapering for an event"),
            "Any peak-form framing must be conditional on intent: \(message)"
        )
    }

    func testBackToBackCrashAddsLoadNote() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 72,
            currentScore: 65,
            nextDayForecast: nil,
            acwr: 1.2,
            injuryRisk: .low,
            activePatterns: ["backToBackCrash"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("back-to-back hard sessions"), "Back-to-back pattern should add load note: \(message)")
        XCTAssertTrue(message.contains("protect tomorrow"), "Load note should warn about tomorrow: \(message)")
    }

    func testSleepFragmentationAddsSleepNote() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 60,
            currentScore: 58,
            nextDayForecast: nil,
            acwr: 1.0,
            injuryRisk: .low,
            activePatterns: ["sleepFragmentation"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("fragmenting"), "Sleep fragmentation pattern should add sleep note: \(message)")
        XCTAssertTrue(message.contains("sleep hygiene"), "Sleep note should mention hygiene: \(message)")
    }

    // MARK: - Enum migration + uncovered primary-path branches

    func testVeryHighInjuryRiskOverride() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85,
            currentScore: 85,
            nextDayForecast: nil,
            acwr: 1.8,
            injuryRisk: .veryHigh
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("injury risk is elevated"), ".veryHigh must trigger the injury-risk override like .high: \(message)")
    }

    func testModerateInjuryRiskDoesNotOverride() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85,
            currentScore: 85,
            nextDayForecast: nil,
            acwr: 1.2,
            injuryRisk: .moderate
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertFalse(message.contains("injury risk is elevated"), ".moderate must not trigger the override: \(message)")
    }

    func testExcellentReadinessPlain() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 88,
            currentScore: 85,
            nextDayForecast: nil,
            acwr: 1.0,
            injuryRisk: .low
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("recovery is excellent (85%)"), "Score >= 80 with no patterns should report excellent recovery: \(message)")
        XCTAssertTrue(message.contains("ready for intensity"), "Excellent plain branch carries the ready verdict: \(message)")
    }

    func testSolidReadinessWithPeakPattern() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 72,
            currentScore: 70,
            nextDayForecast: nil,
            acwr: 1.0,
            injuryRisk: .low,
            activePatterns: ["performancePeak"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("recovery is solid (70%)"), "Score 60-79 with peak pattern should report solid recovery: \(message)")
        XCTAssertTrue(message.contains("peak form window forming"), "Peak pattern should upgrade the solid branch: \(message)")
    }

    func testSolidReadinessWithTaperPattern() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 72,
            currentScore: 70,
            nextDayForecast: nil,
            acwr: 0.75,
            injuryRisk: .low,
            activePatterns: ["tapering"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("training volume is down"), "Taper pattern should upgrade the solid branch: \(message)")
        XCTAssertFalse(
            message.contains("fitness is locked in") || message.contains("Trust the process"),
            "Coach must not assert the volume drop was deliberate — the same signal is injury or illness: \(message)"
        )
    }

    func testSuppressedReadiness() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 56,
            currentScore: 55,
            nextDayForecast: nil,
            acwr: 1.0,
            injuryRisk: .low
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("recovery is suppressed (55%)"), "Score < 60 should report suppressed recovery: \(message)")
        XCTAssertTrue(message.contains("Prioritize rest"), "Suppressed branch should advise rest: \(message)")
    }

    // MARK: - Heuristic fallback path (direct, synchronous)

    func testHeuristic_morningUsedWell() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85, currentScore: 42, nextDayForecast: nil, acwr: 1.1, injuryRisk: .low
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("woke up primed at 85%"), "High-morning big-drop branch: \(message)")
        XCTAssertTrue(message.contains("down to 42% now"), "Should report current score: \(message)")
    }

    func testHeuristic_activeRecovery() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 80, currentScore: 60, nextDayForecast: nil, acwr: 1.1, injuryRisk: .low
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("put in work"), "High-morning moderate-drop branch: \(message)")
        XCTAssertTrue(message.contains("Focus on active recovery"), "Should advise active recovery: \(message)")
    }

    func testHeuristic_startedFatigued() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 60, currentScore: 50, nextDayForecast: nil, acwr: 1.1, injuryRisk: .low
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("started the day fatigued at 60%"), "Low-morning intraday branch: \(message)")
        XCTAssertTrue(message.contains("dropped you to 50%"), "Should report current score: \(message)")
    }

    func testHeuristic_injuryRiskOverride() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 80, currentScore: 80, nextDayForecast: nil, acwr: 1.6, injuryRisk: .veryHigh
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("injury risk is elevated"), "Heuristic path must honor the enum injury-risk override: \(message)")
    }

    func testHeuristic_excellentPlain() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 86, currentScore: 85, nextDayForecast: nil, acwr: 1.0, injuryRisk: .low
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("recovery is excellent (85%)"), "Heuristic excellent plain branch: \(message)")
        XCTAssertTrue(message.contains("ready for intensity"), "Heuristic excellent branch carries the ready verdict: \(message)")
    }

    func testHeuristic_excellentPeak() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 86, currentScore: 85, nextDayForecast: nil, acwr: 1.0, injuryRisk: .low,
            activePatterns: ["performancePeak"]
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("race or benchmark"), "Heuristic excellent+peak branch: \(message)")
    }

    func testHeuristic_excellentTaper() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 86, currentScore: 85, nextDayForecast: nil, acwr: 0.7, injuryRisk: .low,
            activePatterns: ["tapering"]
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(
            message.contains("training volume is down"),
            "Heuristic excellent+taper branch: \(message)"
        )
        XCTAssertTrue(
            message.contains("If you're tapering for an event"),
            "Heuristic path must hedge the peak-form framing on intent too: \(message)"
        )
    }

    func testHeuristic_solidPeak() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 72, currentScore: 70, nextDayForecast: nil, acwr: 1.0, injuryRisk: .low,
            activePatterns: ["performancePeak"]
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("peak form window forming"), "Heuristic solid+peak branch: \(message)")
    }

    func testHeuristic_solidTaper() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 72, currentScore: 70, nextDayForecast: nil, acwr: 0.75, injuryRisk: .low,
            activePatterns: ["tapering"]
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("training volume is down"), "Heuristic solid+taper branch: \(message)")
        XCTAssertFalse(
            message.contains("fitness is locked in") || message.contains("Trust the process"),
            "Heuristic path must not assert intent either: \(message)"
        )
    }

    func testHeuristic_stablePlain() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 70, currentScore: 70, nextDayForecast: nil, acwr: 1.0, injuryRisk: .low
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("70% recovered"), "Heuristic stable plain branch: \(message)")
        XCTAssertTrue(message.contains("moderate work"), "Stable branch should permit moderate work: \(message)")
    }

    func testHeuristic_suppressed() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 50, currentScore: 48, nextDayForecast: nil, acwr: 1.0, injuryRisk: .low
        )
        let message = MasterCoachEngine.generateHeuristicMessage(state: state)

        XCTAssertTrue(message.contains("recovery is suppressed (48%)"), "Heuristic suppressed branch: \(message)")
    }
}
