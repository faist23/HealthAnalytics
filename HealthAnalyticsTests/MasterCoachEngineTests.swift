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
            injuryRisk: "Low"
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("woke up primed at 85%"), "Message should acknowledge morning score: \(message)")
        XCTAssertTrue(message.contains("Current readiness is 42%"), "Message should acknowledge current score: \(message)")
        XCTAssertTrue(message.contains("take it easy"), "Message should advise rest: \(message)")
        XCTAssertTrue(message.contains("rest day tomorrow"), "Message should include forecast: \(message)")
    }

    func testHighInjuryRiskOverride() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85,
            currentScore: 85,
            nextDayForecast: "Hard effort OK",
            acwr: 1.6,
            injuryRisk: "High"
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
            injuryRisk: "Low"
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("readiness is stable (75%)"), "Message should acknowledge stable readiness: \(message)")
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
            injuryRisk: "Low",
            activePatterns: ["hrvPrecursor"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("early warning pattern"), "HRV precursor must override positive readiness: \(message)")
        XCTAssertTrue(message.contains("prioritize sleep"), "HRV precursor must recommend sleep: \(message)")
        XCTAssertFalse(message.contains("nervous system is primed"), "Should not give positive message under HRV precursor: \(message)")
    }

    func testPerformancePeakUpgradesExcellentReadiness() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 88,
            currentScore: 85,
            nextDayForecast: nil,
            acwr: 1.1,
            injuryRisk: "Low",
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
            injuryRisk: "Low",
            activePatterns: ["tapering"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("tapering"), "Taper pattern should be called out: \(message)")
        XCTAssertTrue(message.contains("peak window"), "Taper message should mention peak window: \(message)")
    }

    func testBackToBackCrashAddsLoadNote() async {
        let state = MasterCoachEngine.StateVector(
            morningScore: 72,
            currentScore: 65,
            nextDayForecast: nil,
            acwr: 1.2,
            injuryRisk: "Low",
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
            injuryRisk: "Low",
            activePatterns: ["sleepFragmentation"]
        )
        let message = await MasterCoachEngine.generateMessage(state: state)

        XCTAssertTrue(message.contains("fragmenting"), "Sleep fragmentation pattern should add sleep note: \(message)")
        XCTAssertTrue(message.contains("sleep hygiene"), "Sleep note should mention hygiene: \(message)")
    }
}
