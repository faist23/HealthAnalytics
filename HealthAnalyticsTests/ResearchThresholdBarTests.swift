//
//  ResearchThresholdBarTests.swift
//  HealthAnalyticsTests
//
//  Tests the pure static zone(for:citation:) function — no SwiftUI rendering.
//

import XCTest
@testable import HealthAnalytics

final class ResearchThresholdBarTests: XCTestCase {

    // MARK: - Fixtures

    private var acwrCitation: ScienceCitation { CitationDatabase.citation(for: .acwr)! }
    private var sleepCitation: ScienceCitation { CitationDatabase.citation(for: .sleep)! }
    private var metCitation: ScienceCitation { CitationDatabase.citation(for: .metMinutes)! }
    private var hrvCitation: ScienceCitation { CitationDatabase.citation(for: .hrv)! }

    // MARK: - Nil value → insufficientData

    func testNilValueReturnsInsufficientData() {
        let zone = ResearchThresholdBar.zone(for: nil, citation: acwrCitation)
        XCTAssertEqual(zone.label, .insufficientData)
    }

    // MARK: - ACWR zones

    func testACWRUnderTraining() {
        // 0.5 < 0.8 lower bound → insufficient (under-training)
        let zone = ResearchThresholdBar.zone(for: 0.5, citation: acwrCitation)
        XCTAssertEqual(zone.label, .insufficient)
    }

    func testACWRLowerBoundInclusive() {
        // Exactly 0.8 → optimal (lower bound is inclusive)
        let zone = ResearchThresholdBar.zone(for: 0.8, citation: acwrCitation)
        XCTAssertEqual(zone.label, .optimal)
    }

    func testACWROptimal() {
        // 1.0 within 0.8–1.3 → optimal
        let zone = ResearchThresholdBar.zone(for: 1.0, citation: acwrCitation)
        XCTAssertEqual(zone.label, .optimal)
    }

    func testACWRMonitoring() {
        // 1.4 between 1.3 and 1.5 → monitoring
        let zone = ResearchThresholdBar.zone(for: 1.4, citation: acwrCitation)
        XCTAssertEqual(zone.label, .monitoring)
    }

    func testACWRDanger() {
        // 1.6 ≥ 1.5 dangerAbove → danger
        let zone = ResearchThresholdBar.zone(for: 1.6, citation: acwrCitation)
        XCTAssertEqual(zone.label, .danger)
    }

    func testACWRDangerIsClamped() {
        // 2.1 exceeds bar max (2.0) → clamped
        let zone = ResearchThresholdBar.zone(for: 2.1, citation: acwrCitation)
        XCTAssertEqual(zone.label, .danger)
        XCTAssertTrue(zone.isClamped)
    }

    // MARK: - Sleep zones

    func testSleepOptimal() {
        // 7.5h within 7–9h → optimal
        let zone = ResearchThresholdBar.zone(for: 7.5, citation: sleepCitation)
        XCTAssertEqual(zone.label, .optimal)
    }

    func testSleepBelowOptimal() {
        // 6.5h → monitoring (6–7h zone)
        let zone = ResearchThresholdBar.zone(for: 6.5, citation: sleepCitation)
        XCTAssertEqual(zone.label, .monitoring)
    }

    func testSleepCriticallyLow() {
        // 5.0h < 6h → insufficient
        let zone = ResearchThresholdBar.zone(for: 5.0, citation: sleepCitation)
        XCTAssertEqual(zone.label, .insufficient)
    }

    // MARK: - MET-minutes — WHO 2020 no upper cap

    func testMETOptimalAt600() {
        // 600 = threshold → optimal
        let zone = ResearchThresholdBar.zone(for: 600, citation: metCitation)
        XCTAssertEqual(zone.label, .optimal)
    }

    func testMETHighVolumeIsStillOptimal() {
        // 2000 MET-min — WHO has no upper harm threshold; must be optimal, NOT monitoring
        let zone = ResearchThresholdBar.zone(for: 2000, citation: metCitation)
        XCTAssertEqual(zone.label, .optimal,
            "2000 MET-min must be optimal per WHO 2020 — there is no upper danger zone")
    }

    func testMETInsufficientBelow150() {
        // 100 < 150 → insufficient
        let zone = ResearchThresholdBar.zone(for: 100, citation: metCitation)
        XCTAssertEqual(zone.label, .insufficient)
    }

    // MARK: - HRV % deviation

    func testHRVOptimalBand() {
        // -3% within ±5% of baseline → optimal
        let zone = ResearchThresholdBar.zone(for: -3.0, citation: hrvCitation)
        XCTAssertEqual(zone.label, .optimal)
    }

    func testHRVBelowBaseline() {
        // -20% < -15% → insufficient
        let zone = ResearchThresholdBar.zone(for: -20.0, citation: hrvCitation)
        XCTAssertEqual(zone.label, .insufficient)
    }
}
