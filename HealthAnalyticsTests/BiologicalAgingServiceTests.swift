//
//  BiologicalAgingServiceTests.swift
//  HealthAnalyticsTests
//
//  Encodes the algorithm contract for BiologicalAgingService.
//  Uses the pure-math `computeBiologicalAge` helper to bypass HealthKit + SwiftData.
//
//  Algorithm constants under test:
//    - HRV standard: max(25, 65 - (age-20)*0.8) — Malik et al. 1996 RMSSD norms
//    - Cap: ±8 years (research-defensible range for lifestyle interventions)
//    - VO2 norms: male base 45, female base 40; -0.5 ml/kg/min/year; floor 18
//    - Weights (VO2 available): HRV 45%, RHR 25%, VO2 30%
//    - Weights (no VO2): HRV 60%, RHR 40%
//
//  If these assertions fail after a formula change, the calibration
//  must be re-justified before merging.
//

import XCTest
@testable import HealthAnalytics

final class BiologicalAgingServiceTests: XCTestCase {

    // MARK: - Biological Age Ranges

    func test_fit65yo_biologicalAgeInExpectedRange() {
        // Fit 65yo: HRV=40ms (vs 29ms standard), RHR=52bpm — no VO2 data
        // Lower bound 57 = 65 - 8 (cap floor). Upper from empirical calculation.
        let (bioAge, _, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 65, currentHRV: 40, currentRHR: 52
        )
        XCTAssertGreaterThanOrEqual(bioAge, 57,
            "Fit 65yo should not score below 57 (cap floor = chronoAge - 8). Actual: \(bioAge)")
        XCTAssertLessThanOrEqual(bioAge, 63,
            "Fit 65yo should score below 63. Actual: \(bioAge)")
    }

    func test_average65yo_biologicalAgeNearChronological() {
        // Average 65yo: HRV=29ms (at standard), RHR=65bpm
        let (bioAge, _, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 65, currentHRV: 29, currentRHR: 65
        )
        XCTAssertGreaterThanOrEqual(bioAge, 63,
            "Average 65yo bio age should be ≥63. Actual: \(bioAge)")
        XCTAssertLessThanOrEqual(bioAge, 67,
            "Average 65yo bio age should be ≤67. Actual: \(bioAge)")
    }

    func test_sedentary65yo_biologicalAgeAboveChronological() {
        // Sedentary 65yo: HRV=15ms (below standard), RHR=78bpm
        // Upper bound 73 = 65 + 8 (cap ceiling).
        let (bioAge, _, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 65, currentHRV: 15, currentRHR: 78
        )
        XCTAssertGreaterThan(bioAge, 67,
            "Sedentary 65yo should age faster than 67. Actual: \(bioAge)")
        XCTAssertLessThanOrEqual(bioAge, 73,
            "Cap at +8 years means max 73 for a 65yo. Actual: \(bioAge)")
    }

    // MARK: - ±8 Year Cap

    func test_lowerCapEnforced_veryHighHRV_veryLowRHR() {
        // Very fit profile — should be capped at exactly chronoAge - 8
        let chronoAge = 65
        let (bioAge, alpha, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: chronoAge, currentHRV: 120, currentRHR: 30
        )
        XCTAssertEqual(alpha, 8.0, accuracy: 0.01,
            "Max positive adjustment should be capped at +8. Actual alpha: \(alpha)")
        XCTAssertEqual(bioAge, Double(chronoAge) - 8.0, accuracy: 0.01,
            "Bio age cap: chronoAge - 8. Actual: \(bioAge)")
    }

    func test_upperCapEnforced_veryLowHRV_veryHighRHR() {
        // Very sedentary profile — should be capped at exactly chronoAge + 8
        let chronoAge = 65
        let (bioAge, alpha, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: chronoAge, currentHRV: 5, currentRHR: 110
        )
        XCTAssertEqual(alpha, -8.0, accuracy: 0.01,
            "Max negative adjustment should be capped at -8. Actual alpha: \(alpha)")
        XCTAssertEqual(bioAge, Double(chronoAge) + 8.0, accuracy: 0.01,
            "Bio age cap: chronoAge + 8. Actual: \(bioAge)")
    }

    // MARK: - VO2 Max Pillar

    func test_vo2Nil_gracefulFallback_HRVRHRBlend() {
        // With no VO2 data, weights should be HRV 60% + RHR 40%.
        // A neutral HRV (at standard) with perfect RHR should still produce positive alpha.
        let (_, alpha, vo2MaxRetained) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 40, currentHRV: 45, currentRHR: 55, currentVO2: nil
        )
        XCTAssertNil(vo2MaxRetained, "vo2MaxRetained should be nil when no VO2 data")
        XCTAssertGreaterThan(alpha, 0, "Perfect RHR should produce positive alpha even without VO2")
    }

    func test_vo2Max38_at65_positiveContribution() {
        // VO2=38 at age 65: standard = max(18, 45 - 22.5) = 22.5
        // vo2Adj = (38 - 22.5) / 3 = +5.17 → positive contribution
        let (_, alpha, vo2MaxRetained) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 65, currentHRV: 35, currentRHR: 58, currentVO2: 38.0
        )
        XCTAssertNotNil(vo2MaxRetained, "vo2MaxRetained should be non-nil with VO2 data")
        XCTAssertGreaterThan(alpha, 0, "VO2=38 at 65 should produce positive alpha")
    }

    // MARK: - Female VO2 Norms

    func test_femaleVO2Norms_lowerBaselineApplied() {
        // Female, age 65, VO2=22: standardVO2 = max(18, 40 - 22.5) = max(18, 17.5) = 18.0
        // vo2Adj = (22 - 18) / 3 = +1.33 → positive contribution
        let (_, alphaMale, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 65, currentHRV: 30, currentRHR: 60, currentVO2: 22.0, sex: "male"
        )
        let (_, alphaFemale, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 65, currentHRV: 30, currentRHR: 60, currentVO2: 22.0, sex: "female"
        )
        // Female standard is lower (18 vs 22.5), so same VO2=22 scores better for female
        XCTAssertGreaterThan(alphaFemale, alphaMale,
            "Female norms produce larger positive alpha for same VO2 value. female:\(alphaFemale) male:\(alphaMale)")
    }

    // MARK: - Named Constant (guard on minimumHRVSamples)
    // Test 8 verifies the named constant exists and is 30 —
    // the guard itself can only be exercised with a real ModelContext.

    func test_minimumHRVSamples_namedConstant_is30() {
        // Access the constant to confirm it hasn't drifted from 30.
        // If someone changes the guard threshold, this test surfaces the change.
        let minSamples = BiologicalAgingService.minimumHRVSamples
        XCTAssertEqual(minSamples, 30,
            "minimumHRVSamples must remain 30 — change test range if you change this")
    }

    // Test 9: getUserAge() nil → returns nil
    // Exercised naturally on Simulator (HealthKit returns nil for age).
    // Tested implicitly by the guard at the top of calculateAgingAlpha().
    // No unit test needed — it's a guard, not an algorithm.

    // MARK: - HRV Standard Formula Verification

    func test_standardHRVFormula_age30() {
        // max(25, 65 - (30-20)*0.8) = max(25, 65-8) = 57ms
        let (_, _, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 30, currentHRV: 57, currentRHR: 60
        )
        // At standard HRV + neutral RHR, alpha should be near 0
        let (_, alpha, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 30, currentHRV: 57, currentRHR: 60
        )
        XCTAssertEqual(alpha, 0, accuracy: 0.5,
            "At standard HRV + neutral RHR for age 30, alpha should be near 0. Actual: \(alpha)")
    }

    func test_standardHRVFormula_age65_floor() {
        // max(25, 65 - (65-20)*0.8) = max(25, 65-36) = max(25, 29) = 29ms
        // At exactly 29ms HRV + 60bpm RHR, alpha should be near 0
        let (_, alpha, _) = BiologicalAgingService.computeBiologicalAge(
            chronoAge: 65, currentHRV: 29, currentRHR: 60
        )
        XCTAssertEqual(alpha, 0, accuracy: 1.0,
            "At standard HRV for age 65 + neutral RHR, alpha near 0. Actual: \(alpha)")
    }

    // MARK: - FTP Resolution (PredictiveReadinessService)

    func test_ftpFallback_zero_returns200() {
        UserDefaults.standard.set(0, forKey: "strava_ftp")
        let ftp = PredictiveReadinessService.resolvedFTP()
        XCTAssertEqual(ftp, 200.0, accuracy: 0.01,
            "FTP=0 in UserDefaults should fall back to 200W")
        UserDefaults.standard.removeObject(forKey: "strava_ftp")
    }

    func test_ftpStored_280_returnsStoredValue() {
        UserDefaults.standard.set(280, forKey: "strava_ftp")
        let ftp = PredictiveReadinessService.resolvedFTP()
        XCTAssertEqual(ftp, 280.0, accuracy: 0.01,
            "FTP=280 in UserDefaults should return 280W")
        UserDefaults.standard.removeObject(forKey: "strava_ftp")
    }
}
