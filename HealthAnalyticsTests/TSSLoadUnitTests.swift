//
//  TSSLoadUnitTests.swift
//  HealthAnalyticsTests
//
//  v0.2.1: load is TSS everywhere. A new ride used to read as detraining because it scored
//  about a quarter of its load until its Strava stream landed, and the Coach card worded a
//  load spike as detraining.
//

import XCTest
import HealthKit
import SwiftData
import Combine
@testable import HealthAnalytics

@MainActor
final class TSSLoadUnitTests: XCTestCase {

    private let calendar = Calendar.current
    private let service = PredictiveReadinessService()
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var ftp200: [StoredFTPSnapshot] {
        [StoredFTPSnapshot(date: Date(timeIntervalSince1970: 1_600_000_000), watts: 200, source: "manual")]
    }

    private func ride(daysAgo: Int, hour: Int = 10, minutes: Double = 60, np: Double? = nil, avg: Double? = nil,
                      zones: [Double]? = nil, type: HKWorkoutActivityType = .cycling) -> WorkoutData {
        let start = calendar.date(byAdding: .hour, value: hour,
                                  to: calendar.date(byAdding: .day, value: -daysAgo, to: today)!)!
        return WorkoutData(workoutType: type, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
                           duration: minutes * 60, totalEnergyBurned: nil, totalDistance: nil,
                           averagePower: avg ?? np, normalizedPower: np, powerZoneSeconds: zones,
                           averageHeartRate: nil, source: .strava)
    }

    // MARK: - #1 The detraining bug, reproduced

    // Value: protects=a new ride's ACWR doesn't change when its zones land later;
    //   fails_when=zones outrank NP again, or the paths drift onto different scales (Craig's
    //   2026-11-23 ride: stored 0.73 "detraining" before its stream, 0.90 after);
    //   why_new=the unit change; seam=none; no_claim=Strava's timing
    func test_acwrIsTheSameBeforeAndAfterTodaysStreamLands() {
        let zones: [Double] = [1619, 307, 723, 1872, 3, 0, 0]   // a real 75-min sweet-spot ride
        var history = (1...27).filter { $0 % 2 == 0 }.map { ride(daysAgo: $0, np: 150, zones: [600, 600, 1200, 1200, 0, 0, 0]) }
        let before = history + [ride(daysAgo: 0, hour: 0, minutes: 75, np: 157)]
        history.append(ride(daysAgo: 0, hour: 0, minutes: 75, np: 157, zones: zones))
        let a = service.calculateReadiness(stravaActivities: [], healthKitWorkouts: before, ftpSnapshots: ftp200)
        let b = service.calculateReadiness(stravaActivities: [], healthKitWorkouts: history, ftpSnapshots: ftp200)
        XCTAssertEqual(a.acwr, b.acwr, accuracy: 0.0001)
    }

    // MARK: - Path order

    // Value: protects=a ride with a stream but no NP scores from its zone time; fails_when=the zone
    //   and average-power paths swap order (average power reads high here); why_new=no fixture
    //   carried both; seam=none; no_claim=real stream shapes
    func test_zonesOutrankAveragePowerWithoutNP() {
        let workout = ride(daysAgo: 1, avg: 200, zones: [0, 3600, 0, 0, 0, 0, 0])
        XCTAssertEqual(service.calculateWorkoutLoad(workout, ftpSnapshots: ftp200), 42.25, accuracy: 0.001)
    }

    // Value: protects=a run carrying power (a footpod in Health) isn't priced against cycling FTP;
    //   fails_when=the cycling guard is dropped or widened; why_new=every power fixture was a
    //   ride; seam=none; no_claim=how accurate run TSS is
    func test_nonCyclingWorkoutIgnoresPower() {
        let run = ride(daysAgo: 1, np: 250, zones: [0, 0, 0, 3600, 0, 0, 0], type: .running)
        XCTAssertEqual(service.calculateWorkoutLoad(run, ftpSnapshots: ftp200), 60, accuracy: 0.001)
    }

    // MARK: - #3 Coach card status wording

    // Value: protects=the Coach card's load text matches the band; fails_when=building/
    //   overreaching map to .moderate (worded "low (ACWR < 0.8) … detraining") or detraining
    //   maps to a good status (worded "Sweet Spot"); why_new=the inverted mapping; seam=static
    func test_coachCardLoadStatus_wordsEachBandCorrectly() {
        XCTAssertEqual(ReadinessRepository.loadMetricStatus(for: .detraining), .moderate)
        XCTAssertEqual(ReadinessRepository.loadMetricStatus(for: .optimal), .excellent)
        XCTAssertEqual(ReadinessRepository.loadMetricStatus(for: .building), .needsAttention)
        XCTAssertEqual(ReadinessRepository.loadMetricStatus(for: .overreaching), .needsAttention)
    }

    // MARK: - #4 One ratio on every surface

    // Value: protects=the training-load summary reports the shared engine's ACWR and loads;
    //   fails_when=its own calendar-day/TRIMP ratio comes back (Coach card showed 1.16 beside a
    //   status banded on 0.90); why_new=#4; seam=none
    func test_trainingLoadSummaryReportsTheSharedAssessment() throws {
        var workouts = (0..<28).filter { $0 % 2 == 0 }.map { ride(daysAgo: $0, np: $0 < 7 ? 120 : 160) }
        // Inside the shared engine's 7×24h acute window but on the 8th calendar day back, where a
        // calendar-day ratio leaves it out, so the two ratios differ.
        let edgeStart = Date().addingTimeInterval(-7 * 86400 + 60)
        try XCTSkipIf(!calendar.isDate(edgeStart, inSameDayAs: calendar.date(byAdding: .day, value: -7, to: today)!),
                      "Within a minute of midnight the edge ride lands on another day")
        workouts.append(WorkoutData(workoutType: .cycling, startDate: edgeStart, endDate: edgeStart.addingTimeInterval(7200),
                                    duration: 7200, totalEnergyBurned: nil, totalDistance: nil, averagePower: 200,
                                    normalizedPower: 200, averageHeartRate: nil, source: .strava))
        let assessment = service.calculateReadiness(stravaActivities: [], healthKitWorkouts: workouts, ftpSnapshots: ftp200)
        let summary = try XCTUnwrap(TrainingLoadCalculator().calculateTrainingLoad(
            healthKitWorkouts: workouts, stepData: [], ftpSnapshots: ftp200))
        XCTAssertEqual(summary.acuteChronicRatio, assessment.acwr, accuracy: 0.0001)
        XCTAssertEqual(summary.acuteLoad, assessment.acuteLoad, accuracy: 0.0001)
        XCTAssertEqual(summary.chronicLoad, assessment.chronicLoad, accuracy: 0.0001)
    }

    func test_trainingLoadSummaryTSSIsWorkoutTSS() throws {
        let yesterday = ride(daysAgo: 1, np: 200)   // an hour at FTP
        let summary = try XCTUnwrap(TrainingLoadCalculator().calculateTrainingLoad(
            healthKitWorkouts: [yesterday], stepData: [], ftpSnapshots: ftp200))
        XCTAssertEqual(summary.yesterdayTSS, 100, accuracy: 0.001)
    }

    // Value: protects=steps stay recovery context, never training load; fails_when=the "10k+ steps"
    //   bonus comes back; why_new=every other summary test passes no steps; seam=none;
    //   no_claim=NEAT recovery math
    func test_trainingLoadSummary_stepsAddNoLoad() throws {
        let yesterdayNoon = calendar.date(byAdding: .hour, value: -12, to: today)!
        let summary = try XCTUnwrap(TrainingLoadCalculator().calculateTrainingLoad(
            healthKitWorkouts: [ride(daysAgo: 3, np: 200)],
            stepData: [HealthDataPoint(date: yesterdayNoon, value: 25_000)], ftpSnapshots: ftp200))
        XCTAssertEqual(summary.yesterdayTSS, 0, accuracy: 0.001)
        XCTAssertEqual(summary.weeklyTSS, 100, accuracy: 0.001)
    }

    // MARK: - Load tab: TSS and volume per day

    func test_dailyTraining_sumsTSSAndHoursAndKeepsRestDays() {
        let workouts = [
            ride(daysAgo: 3, np: 200),                         // 100 TSS, 1 h
            ride(daysAgo: 1, hour: 8, minutes: 90, np: 130),   // 0.65² × 1.5 × 100 = 63.4, 1.5 h
            ride(daysAgo: 1, hour: 18, minutes: 30, type: .walking),  // 0.5 h × 25 = 12.5
        ]
        let days = ReadinessRepository.dailyTraining(workouts: workouts, ftpSnapshots: ftp200,
                                                     service: service, now: Date())
        XCTAssertEqual(days.map(\.date), (0...3).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! })
        XCTAssertEqual(days[0].tss, 100, accuracy: 0.01)
        XCTAssertEqual(days[1].tss, 0, "A rest day is present, at zero")
        XCTAssertEqual(days[2].tss, 63.375 + 12.5, accuracy: 0.01)
        XCTAssertEqual(days[2].hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(days[3].hours, 0)
    }

    // Value: protects=the Load tab's fitness (42-day) and fatigue (7-day) lines; fails_when=the
    //   two time constants swap, the average restarts each day, or hours are dropped;
    //   why_new=new function; seam=none; no_claim=chart rendering
    func test_dailyTSSData_fitnessAndFatigueCurves() {
        let days = [ReadinessRepository.DailyTraining(date: today, tss: 100, hours: 1),
                    ReadinessRepository.DailyTraining(date: today.addingTimeInterval(86400), tss: 0, hours: 0)]
        let points = ReadinessViewModel.dailyTSSData(from: days)
        XCTAssertEqual(points[0].atl, 25, accuracy: 0.0001)
        XCTAssertEqual(points[0].ctl, 200.0 / 43.0, accuracy: 0.0001)
        XCTAssertEqual(points[1].atl, 25 * 0.75, accuracy: 0.0001)
        XCTAssertEqual(points[1].ctl, 200.0 / 43.0 * 41.0 / 43.0, accuracy: 0.0001)
        XCTAssertEqual(points.map(\.hours), [1, 0])
    }

    func test_weeklyHoursFormat() {
        XCTAssertEqual(TSSChartCard.formatHours(4.7), "4:42")
        XCTAssertEqual(TSSChartCard.formatHours(0), "0:00")
    }

    // MARK: - Stored history migrates to TSS

    // Value: protects=old rows are rewritten in TSS, strain included; fails_when=the migration
    //   leaves old-unit loads beside new TSS rows (the forecast would read a 1.0 day as rest);
    //   why_new=the unit change; seam=static
    func test_migration_rewritesLoadAndStrainInTSS() {
        let workouts = (1...20).map { ride(daysAgo: $0, np: 200) }   // 100 TSS every day
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let row = StoredDailyScore(date: yesterday, readinessScore: 70, dailyStrain: 0.3, workoutCount: 1, dailyLoad: 2.5)
        ReadinessRepository.migrateDailyScoresToTSS(scores: [row], workouts: workouts,
                                                    ftpSnapshots: ftp200, service: service)
        XCTAssertEqual(row.dailyLoad, 100, accuracy: 0.001)
        let expected = service.calculateReadiness(
            stravaActivities: [], healthKitWorkouts: workouts, ftpSnapshots: ftp200,
            referenceDate: PredictiveReadinessService.windowEnd(for: yesterday)).acwr
        XCTAssertEqual(row.dailyStrain, expected, accuracy: 0.0001)
    }

    // Value: protects=each migrated row holds only its own day's TSS; fails_when=the next-day
    //   bound is lost or a row matches the wrong day; why_new=the first fixture had no ride after
    //   the row's day; seam=none; no_claim=the launch gate
    func test_migration_countsOnlyEachRowsOwnDay() {
        let workouts = (5...20).map { ride(daysAgo: $0, np: 200) }
            + [ride(daysAgo: 1, np: 200), ride(daysAgo: 0, hour: 0, np: 200)]
        let ridden = StoredDailyScore(date: calendar.date(byAdding: .day, value: -1, to: today)!,
                                      readinessScore: 70, dailyStrain: 0.3, workoutCount: 1, dailyLoad: 2.5)
        let rest = StoredDailyScore(date: calendar.date(byAdding: .day, value: -3, to: today)!,
                                    readinessScore: 70, dailyStrain: 0.3, workoutCount: 0, dailyLoad: 2.5)
        ReadinessRepository.migrateDailyScoresToTSS(scores: [ridden, rest], workouts: workouts,
                                                    ftpSnapshots: ftp200, service: service)
        XCTAssertEqual(ridden.dailyLoad, 100, accuracy: 0.001)
        XCTAssertEqual(rest.dailyLoad, 0, accuracy: 0.001)
    }

}

// MARK: - Pattern detection waits for the TSS migration

// Value: protects=pattern detection never reads stored loads still in the old unit (every day
//   would fall under the TSS rest line, so back-to-back and taper patterns go quiet for the
//   throttle window); fails_when=the migration gate in performPatternAnalysis goes;
//   why_new=red-team finding; seam=none; no_claim=the background pass's copy of the gate
@MainActor
final class PatternAnalysisWaitsForTSSMigrationTests: XCTestCase {
    private let stampKey = "lastPatternAnalysisDate"
    private var savedStamp: Any?, savedMigration: Any?

    override func setUp() async throws {
        savedStamp = UserDefaults.standard.object(forKey: stampKey)
        savedMigration = UserDefaults.standard.object(forKey: PredictiveReadinessService.tssMigrationKey)
        try XCTSkipIf(UserDefaults.standard.bool(forKey: "isOnboardingComplete"),
                      "App host is onboarded: launch tasks share ReadinessRepository.shared")
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedStamp, forKey: stampKey)
        UserDefaults.standard.set(savedMigration, forKey: PredictiveReadinessService.tssMigrationKey)
        ReadinessRepository.shared.resetForTesting()
    }

    func test_patternRunBeforeTheMigration_readsNothingAndStampsNothing() async throws {
        UserDefaults.standard.removeObject(forKey: PredictiveReadinessService.tssMigrationKey)
        UserDefaults.standard.removeObject(forKey: stampKey)
        var errorWrites = 0
        let sub = ReadinessRepository.shared.$patternAnalysisError.dropFirst().compactMap { $0 }.sink { _ in errorWrites += 1 }
        defer { sub.cancel() }
        ReadinessRepository.shared.isAppInForeground = { true }
        let container = try ModelContainer(
            for: Schema([TrainingPattern.self, StoredDailyScore.self, StoredWorkout.self, StoredFTPSnapshot.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        await ReadinessRepository.shared.runPatternAnalysis(container: container, trigger: .userRetry)

        // A run that reached the analyzer stamps (success / insufficientData) or writes an error
        // (the simulator's HealthKit refusal).
        XCTAssertNil(UserDefaults.standard.object(forKey: stampKey), "Unstamped, so it runs again after the migration")
        XCTAssertEqual(errorWrites, 0, "Must not reach the analyzer")
    }
}
