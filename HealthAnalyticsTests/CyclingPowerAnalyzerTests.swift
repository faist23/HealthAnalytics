//
//  CyclingPowerAnalyzerTests.swift
//  HealthAnalyticsTests
//
//  Tests pure logic in CyclingPowerAnalyzer and StravaManager.peak5MinAverage.
//  HealthKit and network calls are not exercised — those require device-level testing.
//

import XCTest
import HealthKit
@testable import HealthAnalytics

// MARK: - CyclingPowerAnalyzer pure-logic tests

final class CyclingPowerAnalyzerTests: XCTestCase {

    let analyzer = CyclingPowerAnalyzer()

    // MARK: analyzeCompoundScore guard paths (no singletons invoked)

    func testAnalyzeCompoundScore_emptyWorkouts_returnsNil() async {
        let result = await analyzer.analyzeCompoundScore(workouts: [], weightData: [])
        XCTAssertNil(result, "No workouts → no power data → should return nil")
    }

    @MainActor
    func testAnalyzeCompoundScore_onlyNonCyclingWorkouts_returnsNil() async {
        let run = WorkoutData(
            workoutType: .running,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil, totalDistance: nil,
            averagePower: nil, averageHeartRate: nil,
            source: .appleWatch
        )
        let result = await analyzer.analyzeCompoundScore(workouts: [run], weightData: [])
        XCTAssertNil(result, "No cycling workouts — loop is skipped, should return nil")
    }

    @MainActor
    func testAnalyzeCompoundScore_oldCyclingRideOutsideWindow_returnsNil() async {
        let oldDate = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        let oldRide = WorkoutData(
            workoutType: .cycling,
            startDate: oldDate,
            endDate: oldDate.addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil, totalDistance: nil,
            averagePower: nil, averageHeartRate: nil,
            source: .appleWatch
        )
        let result = await analyzer.analyzeCompoundScore(workouts: [oldRide], weightData: [])
        XCTAssertNil(result, "Ride >30 days ago is filtered by recentRides — should return nil")
    }

    // MARK: determinePhenotype

    func testDeterminePhenotype_climber() {
        // relative > 4.5 && weightKg < 70
        XCTAssertEqual(
            analyzer.determinePhenotype(absolute: 320, relative: 4.8, weightKg: 65),
            "Climber"
        )
    }

    func testDeterminePhenotype_rouleur() {
        // absolute > 350 && relative < 4.0
        XCTAssertEqual(
            analyzer.determinePhenotype(absolute: 380, relative: 3.5, weightKg: 108),
            "Rouleur / Flat Specialist"
        )
    }

    func testDeterminePhenotype_allRounder() {
        // absolute > 300 && relative >= 4.0
        XCTAssertEqual(
            analyzer.determinePhenotype(absolute: 340, relative: 4.2, weightKg: 81),
            "All-Rounder"
        )
    }

    func testDeterminePhenotype_enduranceRider() {
        XCTAssertEqual(
            analyzer.determinePhenotype(absolute: 200, relative: 3.0, weightKg: 67),
            "Endurance Rider"
        )
    }

    func testDeterminePhenotype_highRelativeButHeavy_notClimber() {
        // relative > 4.5 but weightKg >= 70 → climber gate fails
        let phenotype = analyzer.determinePhenotype(absolute: 340, relative: 4.6, weightKg: 75)
        XCTAssertNotEqual(phenotype, "Climber")
    }

    // MARK: determineLevel

    func testDetermineLevel_thresholdBoundaries() {
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 1600), "Elite / Pro")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 2000), "Elite / Pro")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 1100), "Advanced")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 1599), "Advanced")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 750),  "Intermediate")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 1099), "Intermediate")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 450),  "Recreational")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 749),  "Recreational")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 0),    "Beginner")
        XCTAssertEqual(analyzer.determineLevel(compoundScore: 449),  "Beginner")
    }

    // MARK: generateInsight

    func testGenerateInsight_balancedPower() {
        let msg = analyzer.generateInsight(
            compoundScore: 1200, relativeFTP: 4.2, absoluteFTP: 330, phenotype: "All-Rounder"
        )
        XCTAssertTrue(msg.contains("Excellent Compound Score"))
    }

    func testGenerateInsight_highClimbingEfficiency() {
        // relative > 4.5 but absolute < 300 → climbing-efficiency branch
        let msg = analyzer.generateInsight(
            compoundScore: 900, relativeFTP: 4.8, absoluteFTP: 280, phenotype: "Climber"
        )
        XCTAssertTrue(msg.contains("climbing efficiency"))
    }

    func testGenerateInsight_highAbsolutePower() {
        // absolute > 350 but relative < 4.0
        let msg = analyzer.generateInsight(
            compoundScore: 1300, relativeFTP: 3.5, absoluteFTP: 380, phenotype: "Rouleur / Flat Specialist"
        )
        XCTAssertTrue(msg.contains("absolute power"))
    }

    func testGenerateInsight_generic() {
        let msg = analyzer.generateInsight(
            compoundScore: 400, relativeFTP: 2.8, absoluteFTP: 220, phenotype: "Endurance Rider"
        )
        XCTAssertTrue(msg.contains("Consistent training"))
    }
}

// MARK: - StravaManager rolling-window algorithm

final class StravaRollingWindowTests: XCTestCase {

    func testPeak5MinAverage_lessThan300Samples_returnsNil() {
        let samples = Array(repeating: 250.0, count: 299)
        XCTAssertNil(StravaManager.peak5MinAverage(samples: samples))
    }

    func testPeak5MinAverage_exactly300FlatSamples_returnsAverage() throws {
        let samples = Array(repeating: 200.0, count: 300)
        let result = try XCTUnwrap(StravaManager.peak5MinAverage(samples: samples))
        XCTAssertEqual(result, 200.0, accuracy: 0.01)
    }

    func testPeak5MinAverage_peakWindowInMiddle() throws {
        // 300 low + 300 high + 300 low — peak should be found in the high block
        let samples = Array(repeating: 100.0, count: 300)
            + Array(repeating: 400.0, count: 300)
            + Array(repeating: 100.0, count: 300)
        let result = try XCTUnwrap(StravaManager.peak5MinAverage(samples: samples))
        XCTAssertEqual(result, 400.0, accuracy: 0.01)
    }

    func testPeak5MinAverage_nilSubstitutedAsZero() throws {
        // Every other sample is nil (coasting) → substituted 0 → avg ≈ 150
        let rawSamples: [Double?] = (0..<300).map { $0 % 2 == 0 ? 300.0 : nil }
        let samples = rawSamples.map { $0 ?? 0.0 }
        let result = try XCTUnwrap(StravaManager.peak5MinAverage(samples: samples))
        XCTAssertEqual(result, 150.0, accuracy: 0.01)
    }

    func testPeak5MinAverage_allZeroSamples_returnsNil() {
        let samples = Array(repeating: 0.0, count: 400)
        XCTAssertNil(
            StravaManager.peak5MinAverage(samples: samples),
            "All-zero watts (coasting only) should return nil — no real power recorded"
        )
    }
}
