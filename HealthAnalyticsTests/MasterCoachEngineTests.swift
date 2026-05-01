//
//  MasterCoachEngineTests.swift
//  HealthAnalyticsTests
//

import XCTest
@testable import HealthAnalytics

final class MasterCoachEngineTests: XCTestCase {

    func testMorningWorkoutFatigue() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85,
            currentScore: 42,
            nextDayForecast: "Rest recommended",
            acwr: 1.1,
            injuryRisk: "Low"
        )
        let message = MasterCoachEngine.generateMessage(state: state)
        
        XCTAssertTrue(message.contains("woke up primed at 85%"), "Message should acknowledge morning score: \(message)")
        XCTAssertTrue(message.contains("current readiness is 42%"), "Message should acknowledge current score: \(message)")
        XCTAssertTrue(message.contains("take it easy"), "Message should advise rest: \(message)")
        XCTAssertTrue(message.contains("rest day tomorrow"), "Message should include forecast: \(message)")
    }

    func testHighInjuryRiskOverride() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 85,
            currentScore: 85,
            nextDayForecast: "Hard effort OK",
            acwr: 1.6,
            injuryRisk: "High"
        )
        let message = MasterCoachEngine.generateMessage(state: state)
        
        XCTAssertTrue(message.contains("injury risk is elevated"), "Message should warn about injury risk: \(message)")
        XCTAssertTrue(message.contains("hard effort tomorrow"), "Message should include forecast: \(message)")
    }
    
    func testStableReadiness() {
        let state = MasterCoachEngine.StateVector(
            morningScore: 75,
            currentScore: 75,
            nextDayForecast: "Moderate training",
            acwr: 1.0,
            injuryRisk: "Low"
        )
        let message = MasterCoachEngine.generateMessage(state: state)
        
        XCTAssertTrue(message.contains("readiness is stable (75%)"), "Message should acknowledge stable readiness: \(message)")
        XCTAssertTrue(message.contains("expect moderate training tomorrow"), "Message should include forecast: \(message)")
    }
}
