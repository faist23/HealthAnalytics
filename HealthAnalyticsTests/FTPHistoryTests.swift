//
//  FTPHistoryTests.swift
//  HealthAnalyticsTests
//
//  Tests for FTP History Management feature.
//
//  Coverage:
//    - StoredFTPSnapshot.resolved(for:snapshots:) — 6 cases
//    - StoredFTPSnapshot.upsertIfChanged — 3 cases (same-day dedup)
//    - PredictiveReadinessService.calculateWorkoutLoad — zone weights + TSS formula
//

import XCTest
import SwiftData
import HealthKit
@testable import HealthAnalytics

// MARK: - Helpers

private func snap(date: Date, watts: Int, source: String = "manual") -> StoredFTPSnapshot {
    StoredFTPSnapshot(date: date, watts: watts, source: source)
}

private func day(_ iso: String) -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")!
    return f.date(from: iso)!
}

private func makeInMemoryContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: StoredFTPSnapshot.self, configurations: config)
    return ModelContext(container)
}

// MARK: - resolved(for:snapshots:) Tests

final class StoredFTPSnapshotResolvedTests: XCTestCase {

    // Empty → fall back to 200W default
    func test_resolved_emptySnapshots_returns200W() {
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: Date(), snapshots: []),
            200.0
        )
    }

    // Single snapshot before the workout date — use it
    func test_resolved_singleSnapshotBeforeWorkout() {
        let snapshots = [snap(date: day("2025-01-01"), watts: 250)]
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-06-15"), snapshots: snapshots),
            250.0
        )
    }

    // Single snapshot strictly after the workout date — not yet effective → 200W default
    func test_resolved_singleSnapshotAfterWorkout_returnsDefault() {
        let snapshots = [snap(date: day("2025-06-01"), watts: 250)]
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-01-01"), snapshots: snapshots),
            200.0
        )
    }

    // Workout on the exact snapshot date — inclusive boundary (<=), so snapshot is used
    func test_resolved_exactBoundaryDate_included() {
        let boundary = day("2025-03-15")
        let snapshots = [snap(date: boundary, watts: 260)]
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: boundary, snapshots: snapshots),
            260.0
        )
    }

    // FTP returns to a prior value: 250 → 230 → 250.
    // Workout after the second 250W entry should use 250, not 230.
    func test_resolved_ftpReturnsToPriorValue() {
        let snapshots = [
            snap(date: day("2024-01-01"), watts: 250),
            snap(date: day("2024-06-01"), watts: 230), // injury — fitness dropped
            snap(date: day("2025-01-01"), watts: 250)  // back to form
        ]
        // Ride on 2025-02-01 should resolve to the Jan 2025 entry (250W)
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-02-01"), snapshots: snapshots),
            250.0
        )
        // Ride on 2024-08-01 should resolve to the Jun 2024 entry (230W)
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2024-08-01"), snapshots: snapshots),
            230.0
        )
        // Ride on 2024-03-01 should resolve to the Jan 2024 entry (250W)
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2024-03-01"), snapshots: snapshots),
            250.0
        )
    }

    // Workout between two snapshots — uses the earlier one (most recent ≤ date)
    func test_resolved_workoutBetweenTwoSnapshots_usesEarlier() {
        let snapshots = [
            snap(date: day("2025-01-01"), watts: 240),
            snap(date: day("2025-07-01"), watts: 260)
        ]
        // Workout in April sits between them — Jan snapshot is the most recent ≤ April
        XCTAssertEqual(
            StoredFTPSnapshot.resolved(for: day("2025-04-01"), snapshots: snapshots),
            240.0
        )
    }
}

// MARK: - upsertIfChanged (same-day dedup) Tests

@MainActor
final class StoredFTPSnapshotUpsertTests: XCTestCase {

    // Same day, same watts → skip (returns false, no new row)
    func test_upsertIfChanged_sameDaySameWatts_skips() throws {
        let context = try makeInMemoryContext()
        // Pre-insert a snapshot for today
        let today = Calendar.current.startOfDay(for: Date())
        context.insert(StoredFTPSnapshot(date: today, watts: 250, source: "strava_profile"))
        try context.save()

        let inserted = StoredFTPSnapshot.upsertIfChanged(watts: 250, source: "strava_profile", context: context)

        XCTAssertFalse(inserted, "Should skip when same watts already recorded today")
        let all = try context.fetch(FetchDescriptor<StoredFTPSnapshot>())
        XCTAssertEqual(all.count, 1, "No duplicate should be created")
    }

    // Same day, different watts → update in place (no duplicate row created)
    func test_upsertIfChanged_sameDayDifferentWatts_updatesInPlace() throws {
        let context = try makeInMemoryContext()
        let today = Calendar.current.startOfDay(for: Date())
        context.insert(StoredFTPSnapshot(date: today, watts: 250, source: "strava_profile"))
        try context.save()

        let updated = StoredFTPSnapshot.upsertIfChanged(watts: 260, source: "strava_profile", context: context)

        XCTAssertTrue(updated, "Should return true when watts changed on same day")
        let all = try context.fetch(FetchDescriptor<StoredFTPSnapshot>())
        XCTAssertEqual(all.count, 1, "Must update in place — no duplicate row")
        XCTAssertEqual(all.first?.watts, 260, "Watts must reflect the updated value")
    }

    // Different day, same watts → insert.
    // This is the 250→230→250 bug fix: a returning-to-prior-value entry must not be rejected.
    func test_upsertIfChanged_differentDaySameWatts_inserts() throws {
        let context = try makeInMemoryContext()
        // Yesterday had 250W
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        context.insert(StoredFTPSnapshot(date: yesterday, watts: 250, source: "strava_profile"))
        try context.save()

        // Today also resolves to 250W — must insert (different day)
        let inserted = StoredFTPSnapshot.upsertIfChanged(watts: 250, source: "strava_profile", context: context)

        XCTAssertTrue(inserted, "Should insert even when watts match a prior day's entry")
        let all = try context.fetch(FetchDescriptor<StoredFTPSnapshot>())
        XCTAssertEqual(all.count, 2)
    }
}

// MARK: - calculateWorkoutLoad Tests

final class PredictiveReadinessServiceLoadTests: XCTestCase {

    private let service = PredictiveReadinessService()

    // PATH 1: Zone-weighted load.
    // 1 hour entirely in Z5 (index 4, weight 5.5) → load = 5.5
    func test_calculateLoad_zoneWeighted_pureZ5() {
        let zoneSecs: [Double] = [0, 0, 0, 0, 3600, 0, 0]  // 1 hr Z5
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            powerZoneSeconds: zoneSecs,
            averageHeartRate: nil,
            source: .strava
        )
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [])
        XCTAssertEqual(load, 5.5, accuracy: 0.01)
    }

    // Zone weights sum: 1 hr in each of Z1–Z7 = sum of all weights = 30.5
    func test_calculateLoad_zoneWeighted_oneHourEachZone() {
        let zoneSecs = [Double](repeating: 3600.0, count: 7)
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(7 * 3600),
            duration: 7 * 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            powerZoneSeconds: zoneSecs,
            averageHeartRate: nil,
            source: .strava
        )
        let expectedLoad = PredictiveReadinessService.zoneWeights.reduce(0, +)  // 30.5
        XCTAssertEqual(
            service.calculateWorkoutLoad(workout, ftpSnapshots: []),
            expectedLoad,
            accuracy: 0.01
        )
    }

    // PATH 2: NP-based TSS. IF = NP/FTP, TSS = IF² × durationHours
    // NP=200W, FTP=200W → IF=1.0 → TSS = 1.0 × 1.0 = 1.0 per hour
    func test_calculateLoad_npTSS_thresholdEffort_oneHour() {
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            normalizedPower: 200,
            powerZoneSeconds: nil,
            averageHeartRate: nil,
            source: .strava
        )
        // FTP snapshot for today = 200W
        let snapshot = StoredFTPSnapshot(date: Calendar.current.startOfDay(for: Date()), watts: 200, source: "manual")
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [snapshot])
        // IF=1.0, TSS = 1.0² × 1.0hr = 1.0
        XCTAssertEqual(load, 1.0, accuracy: 0.001)
    }

    // NP=240W, FTP=200W → IF=1.2 → TSS = 1.44 × 1.0hr = 1.44
    func test_calculateLoad_npTSS_aboveThreshold_oneHour() {
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            normalizedPower: 240,
            powerZoneSeconds: nil,
            averageHeartRate: nil,
            source: .strava
        )
        let snapshot = StoredFTPSnapshot(date: Calendar.current.startOfDay(for: Date()), watts: 200, source: "manual")
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [snapshot])
        XCTAssertEqual(load, 1.44, accuracy: 0.001)
    }

    // PATH 1 takes priority over PATH 2 when both zone data and NP are present
    func test_calculateLoad_zonePriorityOverNP() {
        // 1 hr Z1 only (weight 0.5) — load should be 0.5
        // NP=250W with 200W FTP would give TSS = (1.25)² × 1.0 = 1.5625 — different
        let zoneSecs: [Double] = [3600, 0, 0, 0, 0, 0, 0]
        let workout = WorkoutData(
            workoutType: .cycling,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            averagePower: nil,
            normalizedPower: 250,
            powerZoneSeconds: zoneSecs,
            averageHeartRate: nil,
            source: .strava
        )
        let snapshot = StoredFTPSnapshot(date: Calendar.current.startOfDay(for: Date()), watts: 200, source: "manual")
        let load = service.calculateWorkoutLoad(workout, ftpSnapshots: [snapshot])
        XCTAssertEqual(load, 0.5, accuracy: 0.01, "Zone path should win over NP path")
    }
}
