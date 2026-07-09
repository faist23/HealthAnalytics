//
//  TrainingLoadACWRConsistencyTests.swift
//  HealthAnalyticsTests
//
//  Regression tests for the duplicate-ACWR-engine bug (2026-07-09):
//  the Extended Analysis screen computed its own ACWR from a duration-only
//  "hours × 100" TSS and excluded the current day, reporting 1.80/Overreaching
//  while the Load tab's canonical assessment said 1.33/Building. Its 90-day
//  chart also fabricated a 4.0 spike wherever the 28-day chronic window
//  preceded the available data ((T/7)/(T/28) = 4.0 by construction).
//

import XCTest
import HealthKit
@testable import HealthAnalytics

final class TrainingLoadACWRConsistencyTests: XCTestCase {

    private let readinessService = PredictiveReadinessService()
    private let vizService = TrainingLoadVisualizationService()

    // MARK: - Fixtures

    /// Workout `daysAgo - 0.5` days before now (half-day offset keeps every
    /// fixture safely inside window boundaries).
    private func workout(daysAgo: Double, hours: Double, type: HKWorkoutActivityType) -> WorkoutData {
        let start = Date().addingTimeInterval(-(daysAgo - 0.5) * 86_400)
        return WorkoutData(
            workoutType: type,
            startDate: start,
            endDate: start.addingTimeInterval(hours * 3600),
            duration: hours * 3600,
            totalEnergyBurned: nil, totalDistance: nil,
            averagePower: nil, averageHeartRate: nil,
            source: .appleWatch
        )
    }

    /// 21 older days (7.5–27.5 days ago) at 1h cycling/day, plus `acuteHoursPerDay`
    /// cycling on each of the last 7 days (0.5–6.5 days ago).
    /// ACWR = 4a / (21 + a) where a = 7 × acuteHoursPerDay (cycling multiplier 1.0).
    private func fixture(acuteHoursPerDay: Double) -> [WorkoutData] {
        var workouts: [WorkoutData] = []
        for day in 8...28 {
            workouts.append(workout(daysAgo: Double(day), hours: 1.0, type: .cycling))
        }
        if acuteHoursPerDay > 0 {
            for day in 1...7 {
                workouts.append(workout(daysAgo: Double(day), hours: acuteHoursPerDay, type: .cycling))
            }
        }
        return workouts
    }

    // MARK: - One ACWR across surfaces

    /// The Extended Analysis header must equal the Load tab's assessment exactly.
    /// Mixed sport types + a same-day workout are the inputs that exposed the old
    /// divergence: duration-only load ignored sport multipliers, and the old
    /// start-of-day window excluded today's workout.
    func testExtendedAnalysisACWRMatchesLoadTabAssessment() {
        var workouts: [WorkoutData] = []
        for day in 1...35 {
            let type: HKWorkoutActivityType = day % 3 == 0 ? .running : (day % 3 == 1 ? .cycling : .walking)
            workouts.append(workout(daysAgo: Double(day), hours: 1.0, type: type))
        }
        // A workout earlier today — the old window math (`< startOfDay(today)`) dropped it.
        let todayStart = Date().addingTimeInterval(-2 * 3600)
        workouts.append(WorkoutData(
            workoutType: .running,
            startDate: todayStart,
            endDate: todayStart.addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil, totalDistance: nil,
            averagePower: nil, averageHeartRate: nil,
            source: .appleWatch
        ))

        let assessment = readinessService.calculateReadiness(
            stravaActivities: [], healthKitWorkouts: workouts, ftpSnapshots: []
        )
        let viz = vizService.generateLoadVisualization(
            workouts: workouts, labels: [], ftpSnapshots: [], daysBack: 90
        )

        XCTAssertEqual(viz.summary.currentACWR, assessment.acwr, accuracy: 0.01,
            "Extended Analysis and the Load tab must report the same ACWR for the same workouts")
    }

    // MARK: - Cold-start trim

    /// With 40 days of data and a 90-day chart request, the series must begin
    /// no earlier than (first workout + 28 days) and must never contain the
    /// fabricated (T/7)/(T/28) = 4.0 cold-start spike.
    func testTimeSeriesTrimsColdStartArtifact() {
        var workouts: [WorkoutData] = []
        for day in 1...40 {
            workouts.append(workout(daysAgo: Double(day), hours: 1.0, type: .cycling))
        }
        let earliest = workouts.map(\.startDate).min()!
        let calendar = Calendar.current
        let earliestValidDay = calendar.date(byAdding: .day, value: 28, to: calendar.startOfDay(for: earliest))!

        let viz = vizService.generateLoadVisualization(
            workouts: workouts, labels: [], ftpSnapshots: [], daysBack: 90
        )

        XCTAssertFalse(viz.timeSeriesData.isEmpty, "40 days of data must yield a non-empty series")
        XCTAssertGreaterThanOrEqual(viz.timeSeriesData.first!.date, earliestValidDay,
            "Chart must not include days whose 28-day chronic window precedes the data")
        for point in viz.timeSeriesData {
            XCTAssertLessThan(point.acwr, 3.5,
                "No fabricated cold-start spike (uniform 1h/day can never reach ACWR 3.5)")
        }
    }

    /// With 118 days of workout history (the 90-day chart window + 28-day chronic
    /// lead-in that ReadinessRepository now reads), the trimmed series must fill a
    /// full ~90 days — not 62 (90 minus the cold-start trim). Regression for the
    /// "90-day analysis only shows 60 days" report.
    func testTimeSeriesFills90DaysGiven118DaysOfHistory() {
        var workouts: [WorkoutData] = []
        for day in 1...118 {
            workouts.append(workout(daysAgo: Double(day), hours: 1.0, type: .cycling))
        }
        let viz = vizService.generateLoadVisualization(
            workouts: workouts, labels: [], ftpSnapshots: [], daysBack: 90
        )
        let span = viz.timeSeriesData.count
        XCTAssertGreaterThanOrEqual(span, 88,
            "118 days of history must fill the full 90-day window (got \(span) days) — a 90-day fetch would only yield ~62")
        XCTAssertLessThanOrEqual(span, 91, "Series must not exceed the 90-day window")
    }

    /// No workouts at all → empty series, no crash, "Need more data" summary.
    func testTimeSeriesEmptyWorkoutsReturnsEmpty() {
        let viz = vizService.generateLoadVisualization(
            workouts: [], labels: [], ftpSnapshots: [], daysBack: 90
        )
        XCTAssertTrue(viz.timeSeriesData.isEmpty)
        XCTAssertEqual(viz.summary.recommendation, "Need more data")
    }

    // MARK: - Shared status taxonomy

    /// ACWR ≈ 1.6 → assessment says .overreaching AND the chart point says .danger.
    /// Before the fix the assessment enum had no overreaching tier: everything
    /// above 1.3 was labeled "Building" with no upper bound.
    func testOverreachingTierAgreesAcrossBothTaxonomies() {
        let workouts = fixture(acuteHoursPerDay: 2.0)  // 4×14/(21+14) = 1.6

        let assessment = readinessService.calculateReadiness(
            stravaActivities: [], healthKitWorkouts: workouts, ftpSnapshots: []
        )
        XCTAssertEqual(assessment.trend, .overreaching,
            "ACWR \(assessment.acwr) > 1.5 must be overreaching, not building")

        let viz = vizService.generateLoadVisualization(
            workouts: workouts, labels: [], ftpSnapshots: [], daysBack: 90
        )
        XCTAssertEqual(viz.timeSeriesData.last?.status, .danger,
            "Chart status must agree with the assessment tier for the same ACWR")
        XCTAssertEqual(viz.summary.currentStatus, "Overreaching")
    }

    /// ACWR ≈ 1.4 stays in the building band on both taxonomies.
    func testBuildingTierAgreesAcrossBothTaxonomies() {
        let workouts = fixture(acuteHoursPerDay: 97.0 / 60.0)  // a≈11.32 → ACWR≈1.40

        let assessment = readinessService.calculateReadiness(
            stravaActivities: [], healthKitWorkouts: workouts, ftpSnapshots: []
        )
        XCTAssertEqual(assessment.trend, .building,
            "ACWR \(assessment.acwr) in (1.3, 1.5] must be building")

        let viz = vizService.generateLoadVisualization(
            workouts: workouts, labels: [], ftpSnapshots: [], daysBack: 90
        )
        XCTAssertEqual(viz.timeSeriesData.last?.status, .building)
        XCTAssertEqual(viz.summary.currentStatus, "Building")
    }

    /// Uniform load → ACWR 1.0 → optimal; empty acute week → detraining.
    func testOptimalAndDetrainingTiers() {
        let uniform = fixture(acuteHoursPerDay: 1.0)  // 4×7/(21+7) = 1.0
        XCTAssertEqual(
            readinessService.calculateReadiness(stravaActivities: [], healthKitWorkouts: uniform, ftpSnapshots: []).trend,
            .optimal
        )

        let restWeek = fixture(acuteHoursPerDay: 0)  // acute 0 → ACWR 0
        XCTAssertEqual(
            readinessService.calculateReadiness(stravaActivities: [], healthKitWorkouts: restWeek, ftpSnapshots: []).trend,
            .detraining
        )
    }
}
