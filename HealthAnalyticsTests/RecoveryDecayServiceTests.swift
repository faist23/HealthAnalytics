//
//  RecoveryDecayServiceTests.swift
//  HealthAnalyticsTests
//
//  Pure-logic tests for RecoveryDecayService. No HealthKit or SwiftData required.
//

import XCTest
import HealthKit
@testable import HealthAnalytics

final class RecoveryDecayServiceTests: XCTestCase {

    let service = RecoveryDecayService()

    // MARK: - overnightRecoveryMultiplier

    func testOvernightMultiplier_noWorkoutTSS_alwaysOne() {
        XCTAssertEqual(
            RecoveryDecayService.overnightRecoveryMultiplier(workoutTSS: 0, stepExcessTSS: 100),
            1.0,
            "Step excess alone must never impair overnight recovery"
        )
    }

    func testOvernightMultiplier_lowCombinedLoad_alwaysOne() {
        // Combined < 25.0 threshold → no impairment
        XCTAssertEqual(
            RecoveryDecayService.overnightRecoveryMultiplier(workoutTSS: 20, stepExcessTSS: 4),
            1.0,
            accuracy: 0.001
        )
    }

    func testOvernightMultiplier_midpointLoad_linearRamp() {
        // At 1.5× threshold (37.5 TSS total) → midpoint: reduction = (37.5-25)/25 * 0.5 = 0.25 → multiplier = 0.75
        let result = RecoveryDecayService.overnightRecoveryMultiplier(workoutTSS: 30, stepExcessTSS: 7.5)
        XCTAssertEqual(result, 0.75, accuracy: 0.01)
    }

    func testOvernightMultiplier_highCombinedLoad_floorsAtPoint5() {
        // Very high load (e.g. 200 TSS) → floor at 0.5
        let result = RecoveryDecayService.overnightRecoveryMultiplier(workoutTSS: 150, stepExcessTSS: 50)
        XCTAssertGreaterThanOrEqual(result, 0.5)
        XCTAssertLessThanOrEqual(result, 1.0)
        XCTAssertEqual(result, 0.5, accuracy: 0.001)
    }

    // MARK: - NEAT Mechanism 1: step excess adds to intra-day strain

    func testStepExcess_noWorkoutsNoCarryForward_reducesScore() {
        // No workouts, no prior fatigue — baseline 70, step excess 6.0 TSS
        // Should push below 70 (step excess adds to totalCurrentFatigue)
        let result = service.calculateIntraDayReadiness(
            baselineScore: 70,
            todayWorkouts: [],
            priorDayFatigueImpact: 0,
            todayStepExcessTSS: 6.0,
            overnightRecoveryMultiplier: 1.0,
            now: Date()
        )
        XCTAssertLessThan(result.currentScore, 70, "Step excess must reduce current score below baseline")
        XCTAssertGreaterThanOrEqual(result.currentScore, 0)
    }

    func testStepExcess_zero_doesNotAlterScore() {
        // Zero step excess → score equals baseline (no workouts, no carry-forward)
        let result = service.calculateIntraDayReadiness(
            baselineScore: 75,
            todayWorkouts: [],
            priorDayFatigueImpact: 0,
            todayStepExcessTSS: 0,
            overnightRecoveryMultiplier: 1.0,
            now: Date()
        )
        XCTAssertEqual(result.currentScore, 75)
    }

    func testStepExcess_highValue_cappedAt50FatiguePoints() {
        // Even if step TSS is absurdly high, fatigueImpact is capped at 50 → score ≥ 0
        let result = service.calculateIntraDayReadiness(
            baselineScore: 80,
            todayWorkouts: [],
            priorDayFatigueImpact: 0,
            todayStepExcessTSS: 999,
            overnightRecoveryMultiplier: 1.0,
            now: Date()
        )
        XCTAssertGreaterThanOrEqual(result.currentScore, 0)
        XCTAssertLessThanOrEqual(result.fatigueImpact, 50)
    }

    @MainActor
    func testStepExcess_additivelyCombinesWithWorkoutFatigue() {
        // Confirm that step excess adds on top of workout fatigue, making score lower
        // than workout-only scenario (no step excess) vs workout + step excess.
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let twoHoursAgo = startOfDay.addingTimeInterval(2 * 3600)
        let oneHourAgo = startOfDay.addingTimeInterval(3 * 3600)

        // Build a workout that completed before now
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: twoHoursAgo,
            endDate: oneHourAgo,
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            averageHeartRate: 140,
            source: .appleWatch
        )

        let withoutSteps = service.calculateIntraDayReadiness(
            baselineScore: 80,
            todayWorkouts: [workout],
            priorDayFatigueImpact: 0,
            todayStepExcessTSS: 0,
            overnightRecoveryMultiplier: 1.0,
            now: now
        )

        let withSteps = service.calculateIntraDayReadiness(
            baselineScore: 80,
            todayWorkouts: [workout],
            priorDayFatigueImpact: 0,
            todayStepExcessTSS: 3.0,
            overnightRecoveryMultiplier: 1.0,
            now: now
        )

        XCTAssertLessThanOrEqual(
            withSteps.currentScore, withoutSteps.currentScore,
            "Adding step excess must not increase current score"
        )
    }
}
