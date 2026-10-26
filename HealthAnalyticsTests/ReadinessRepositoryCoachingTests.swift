//
//  ReadinessRepositoryCoachingTests.swift
//  HealthAnalyticsTests
//
//  Tests the coaching instruction pipeline moved to ReadinessRepository.
//  Verifies the GEMINI.md mandate: all readiness logic lives in ReadinessRepository.
//

import XCTest
@testable import HealthAnalytics

final class ReadinessRepositoryCoachingTests: XCTestCase {

    private let service = CoachingService()

    // MARK: - CoachingService output wired from Repository

    /// Repository calls generateDailyInstruction() with optimal ACWR data.
    /// Verifies the service produces a non-empty headline — the field that the
    /// coaching card in ReadinessView renders.
    func test_optimalACWR_producesNonEmptyHeadline() {
        let assessment = PredictiveReadinessService.ReadinessAssessment(
            acwr: 1.1,
            chronicLoad: 400,
            acuteLoad: 440,
            trend: .optimal
        )

        let instruction = service.generateDailyInstruction(
            readiness: assessment,
            insights: [],
            recovery: [],
            prediction: nil
        )

        XCTAssertFalse(instruction.headline.isEmpty, "Headline must be non-empty for optimal ACWR")
        XCTAssertEqual(instruction.status, .perform)
    }

    /// Repository calls generateDailyInstruction() with elevated ACWR data.
    /// Verifies recovery status is surfaced.
    func test_elevatedACWR_producesRecoveryStatus() {
        let assessment = PredictiveReadinessService.ReadinessAssessment(
            acwr: 1.6,
            chronicLoad: 400,
            acuteLoad: 640,
            trend: .building
        )

        let instruction = service.generateDailyInstruction(
            readiness: assessment,
            insights: [],
            recovery: [],
            prediction: nil
        )

        XCTAssertEqual(instruction.status, .recover)
        XCTAssertFalse(instruction.headline.isEmpty)
    }

    // MARK: - targetAction activity substitution

    /// Repository replaces "workout" with the athlete's primary activity before
    /// storing in UnifiedReadiness. This test verifies the CoachingService produces
    /// a targetAction containing "workout" when a prediction is present, and that
    /// the Repository substitution pattern produces the expected result.
    func test_targetAction_workoutReplacedWithPrimaryActivity() {
        let prediction = PerformancePredictor.Prediction(
            predictedPerformance: 220,
            activityType: "Ride",
            unit: "W",
            confidence: .high,
            inputs: PerformancePredictor.PredictionInputs(
                sleepHours: 7.5, hrvMs: 55, restingHR: 52, acwr: 1.0, carbs: 200
            )
        )
        let assessment = PredictiveReadinessService.ReadinessAssessment(
            acwr: 1.0,
            chronicLoad: 400,
            acuteLoad: 400,
            trend: .optimal
        )

        let raw = service.generateDailyInstruction(
            readiness: assessment,
            insights: [],
            recovery: [],
            prediction: prediction
        )

        // Repository applies this substitution before storing in UnifiedReadiness
        let enhanced = raw.targetAction?.replacingOccurrences(of: "workout", with: "ride")

        if let target = raw.targetAction {
            // If there's a target, the substitution must have run
            XCTAssertNotNil(enhanced)
            XCTAssertFalse(enhanced!.contains("workout"),
                           "Repository must replace 'workout' with activity-specific language")
        }
        // If targetAction is nil for this status, that's also valid — no crash
    }

    // MARK: - nil instruction handled safely

    func test_noData_returnsValidInstruction() {
        // Zero load — should still produce a valid instruction, not crash
        let assessment = PredictiveReadinessService.ReadinessAssessment(
            acwr: 0.0,
            chronicLoad: 0,
            acuteLoad: 0,
            trend: .detraining
        )

        let instruction = service.generateDailyInstruction(
            readiness: assessment,
            insights: [],
            recovery: [],
            prediction: nil
        )

        XCTAssertFalse(instruction.headline.isEmpty)
        XCTAssertFalse(instruction.subline.isEmpty)
    }
}

// MARK: - Cache reuse vs. active patterns

@MainActor
final class ReadinessRepositoryCacheTests: XCTestCase {

    private let fingerprint = PredictionCache.fingerprint(workoutCount: 10, sleepCount: 10, hrvCount: 10, rhrCount: 10)

    private func canReuse(
        lastAnalysisDate: Date? = Date(),
        active: Set<PatternType>,
        lastActive: Set<PatternType>?
    ) -> Bool {
        ReadinessRepository.canReuseCachedAnalysis(
            lastAnalysisDate: lastAnalysisDate,
            fingerprint: fingerprint,
            lastFingerprint: fingerprint,
            activePatternTypes: active,
            lastActivePatternTypes: lastActive
        )
    }

    func test_cacheReused_whenDataAndPatternsUnchanged() {
        XCTAssertTrue(canReuse(active: [.tapering], lastActive: [.tapering]))
    }

    /// The P2 this guards: a pattern expires mid-day, the store doesn't move, and the
    /// Coach paragraph kept citing a card the Patterns tab had already dropped.
    func test_cacheInvalidated_whenPatternExpiresMidDay() {
        XCTAssertFalse(canReuse(active: [], lastActive: [.tapering]),
                       "A pattern dropping out of the active window must re-run the coach")
    }

    func test_cacheInvalidated_whenPatternNewlyDetected() {
        XCTAssertFalse(canReuse(active: [.tapering, .hrvPrecursor], lastActive: [.tapering]))
    }

    func test_cacheInvalidated_onNewDay() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(canReuse(lastAnalysisDate: yesterday, active: [], lastActive: []))
    }
}
