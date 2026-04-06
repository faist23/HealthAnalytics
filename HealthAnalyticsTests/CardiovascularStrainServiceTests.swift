//
//  CardiovascularStrainServiceTests.swift
//  HealthAnalyticsTests
//
//  Validates the normalization calibration and zone thresholds for
//  CardiovascularStrainService. These tests encode scientific claims:
//    - Hard 60-min Z4-5 effort (90% HRR) → STRENUOUS (13+)
//    - All-out 90-min effort (95% HRR) → capped at 21
//    - Rest day (no samples) → 0, insufficient quality
//    - HR below 20% HRR floor → contributes 0
//    - 30-min gap between samples → filtered out, 0 strain
//
//  If these assertions fail after a normalization change, the calibration
//  must be re-justified before merging.
//

import XCTest
@testable import HealthAnalytics

final class CardiovascularStrainServiceTests: XCTestCase {

    private let service = CardiovascularStrainService()

    // MARK: - Helpers

    /// Generates evenly-spaced 1-minute HR samples.
    private func makeSamples(
        durationMinutes: Int,
        avgBPM: Double,
        startDate: Date = Date()
    ) -> [(date: Date, bpm: Double)] {
        (0...durationMinutes).map { i in
            (date: startDate.addingTimeInterval(Double(i) * 60), bpm: avgBPM)
        }
    }

    // MARK: - Normalization calibration

    func test_hardSixtyMinuteZone4_5_scoresStrenuous() {
        // 90% HRR for 60 minutes — the prototypical hard effort.
        // Raw: pow(0.9, 2) * 60 = 48.6 → strain = 48.6 / 70 * 21 ≈ 14.6
        let maxHR: Double = 176
        let restingHR: Double = 50
        let bpm = restingHR + (maxHR - restingHR) * 0.9   // ≈ 163 bpm

        let samples = makeSamples(durationMinutes: 60, avgBPM: bpm)
        let result = service.compute(todayHRSamples: samples, estimatedMaxHR: maxHR, restingHR: restingHR)

        XCTAssertGreaterThanOrEqual(result.strain, 13.0,
            "Hard 60-min Z4-5 should reach STRENUOUS (13+). Actual: \(result.strain). " +
            "Check normalization constant if this fails.")
        XCTAssertLessThan(result.strain, 21.0,
            "Hard 60-min Z4-5 should not be capped at 21 — that's reserved for all-out efforts.")
    }

    func test_allOutNinetyMinutes_capsAtTwentyOne() {
        // 95% HRR for 90 minutes — race / all-out effort.
        // Raw: pow(0.95, 2) * 90 = 81.2 → strain = 81.2 / 70 * 21 ≈ 24.4 → capped at 21
        let maxHR: Double = 190
        let restingHR: Double = 50
        let bpm = restingHR + (maxHR - restingHR) * 0.95   // ≈ 183 bpm

        let samples = makeSamples(durationMinutes: 90, avgBPM: bpm)
        let result = service.compute(todayHRSamples: samples, estimatedMaxHR: maxHR, restingHR: restingHR)

        XCTAssertEqual(result.strain, 21.0, accuracy: 0.01,
            "All-out 90-min effort should be capped at 21. Actual: \(result.strain)")
    }

    func test_restDay_emptyInput_scoresZero() {
        let result = service.compute(todayHRSamples: [], estimatedMaxHR: 176, restingHR: 50)
        XCTAssertEqual(result.strain, 0)
        XCTAssertEqual(result.dataQuality, .insufficient)
        XCTAssertEqual(result.sampleCount, 0)
    }

    func test_belowHRRFloor_contributesZeroStrain() {
        // 15% HRR is below the 20% floor — should contribute nothing.
        let maxHR: Double = 176
        let restingHR: Double = 60
        let bpm = restingHR + (maxHR - restingHR) * 0.15   // 15% HRR

        let samples = makeSamples(durationMinutes: 60, avgBPM: bpm)
        let result = service.compute(todayHRSamples: samples, estimatedMaxHR: maxHR, restingHR: restingHR)

        XCTAssertEqual(result.strain, 0, accuracy: 0.01,
            "HR below 20% HRR floor should contribute zero strain.")
    }

    // MARK: - Gap filtering

    func test_thirtyMinGap_isFiltered() {
        // Two HR readings 30 minutes apart should be skipped (gap > 10 min rule).
        let now = Date()
        let samples: [(date: Date, bpm: Double)] = [
            (date: now,                             bpm: 160),
            (date: now.addingTimeInterval(30 * 60), bpm: 160)
        ]
        let result = service.compute(todayHRSamples: samples, estimatedMaxHR: 176, restingHR: 50)
        XCTAssertEqual(result.strain, 0, accuracy: 0.01,
            "30-min gap between samples should be filtered, contributing zero strain.")
    }

    func test_tenMinGap_isIncluded() {
        // A 10-minute gap is on the boundary — the guard is `timeDeltaMinutes <= 10`, so it IS included.
        let now = Date()
        let bpm: Double = 160
        let samples: [(date: Date, bpm: Double)] = [
            (date: now,                             bpm: bpm),
            (date: now.addingTimeInterval(10 * 60), bpm: bpm)
        ]
        let result = service.compute(todayHRSamples: samples, estimatedMaxHR: 176, restingHR: 50)
        XCTAssertGreaterThan(result.strain, 0,
            "A 10-minute gap is at the boundary and should be included.")
    }

    // MARK: - Data quality thresholds

    func test_dataQuality_thresholds() {
        let maxHR: Double = 176
        let restingHR: Double = 50
        let bpm: Double = 140

        let empty = service.compute(todayHRSamples: [], estimatedMaxHR: maxHR, restingHR: restingHR)
        XCTAssertEqual(empty.dataQuality, .insufficient, "0 samples → insufficient")

        // makeSamples(durationMinutes: N) generates N+1 samples (0...N inclusive).
        // So durationMinutes: 48 → 49 samples (insufficient), 49 → 50 samples (fair).
        let sparse = makeSamples(durationMinutes: 48, avgBPM: bpm)
        let sparseResult = service.compute(todayHRSamples: sparse, estimatedMaxHR: maxHR, restingHR: restingHR)
        XCTAssertEqual(sparseResult.dataQuality, .insufficient, "49 samples → insufficient")

        let fair = makeSamples(durationMinutes: 49, avgBPM: bpm)
        let fairResult = service.compute(todayHRSamples: fair, estimatedMaxHR: maxHR, restingHR: restingHR)
        XCTAssertEqual(fairResult.dataQuality, .fair, "50 samples → fair")

        let good = makeSamples(durationMinutes: 500, avgBPM: bpm)
        let goodResult = service.compute(todayHRSamples: good, estimatedMaxHR: maxHR, restingHR: restingHR)
        XCTAssertEqual(goodResult.dataQuality, .good, "501 samples → good")
    }

    // MARK: - Zone label consistency

    func test_zoneBoundaries_areCorrect() {
        // Validates the half-open boundaries: [0,7) LIGHT, [7,13) MODERATE, [13,18) STRENUOUS, [18,21] ALL-OUT
        let expectations: [(Double, String)] = [
            (0.0,  "LIGHT"),
            (6.9,  "LIGHT"),
            (7.0,  "MODERATE"),
            (12.9, "MODERATE"),
            (13.0, "STRENUOUS"),
            (17.9, "STRENUOUS"),
            (18.0, "ALL-OUT"),
            (21.0, "ALL-OUT"),
        ]
        for (strain, expected) in expectations {
            XCTAssertEqual(CardiovascularStrainService.label(for: strain), expected,
                           "Strain \(strain) should be \(expected)")
        }
    }

    func test_insufficientHRRange_returnsZeroStrain() {
        // If maxHR - restingHR <= 10, the calculation is undefined — should return 0.
        let result = service.compute(
            todayHRSamples: makeSamples(durationMinutes: 60, avgBPM: 80),
            estimatedMaxHR: 90,
            restingHR: 85  // range = 5, below the 10 bpm guard
        )
        XCTAssertEqual(result.strain, 0,
            "HR range ≤ 10 bpm is physiologically invalid — should return 0.")
    }
}
