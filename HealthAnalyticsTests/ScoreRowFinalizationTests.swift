//
//  ScoreRowFinalizationTests.swift
//  HealthAnalyticsTests
//
//  Pins which stored score days get recomputed. A row written mid-afternoon on the
//  user's last open must be recomputed once that day is complete; today is never
//  recomputed (its row stays foreground-only).
//

import XCTest
@testable import HealthAnalytics

final class ScoreRowFinalizationTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    /// An upgrading user has no marker but may have up to 90 days of mid-day rows the
    /// old backfill froze. The first run recomputes the whole horizon once; the marker
    /// then bounds every later run.
    func test_neverFinalized_recomputesTheWholeHorizonOnce() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: nil, now: Date())
        XCTAssertEqual(range, day(-ScoreRowFinalization.maxRecomputeDays)...day(-1))
        XCTAssertEqual(range?.lowerBound, day(-90))
    }

    /// Last open was 3 days ago, which finalized through 4 days ago. The open day's
    /// partial row (day -3) and everything after it through yesterday get recomputed.
    func test_lastOpenThreeDaysAgo_recomputesFromThatDayThroughYesterday() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: day(-4), now: Date())
        XCTAssertEqual(range, day(-3)...day(-1))
    }

    func test_alreadyFinalizedThroughYesterday_nothingDue() {
        XCTAssertNil(ScoreRowFinalization.recomputeRange(finalizedThrough: day(-1), now: Date()))
    }

    func test_neverIncludesToday() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: day(-10), now: Date())
        XCTAssertEqual(range?.upperBound, day(-1))
    }

    /// Review focus 5: a long absence is bounded by the backfill horizon.
    func test_longAbsence_isBoundedToNinetyDays() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: day(-400), now: Date())
        XCTAssertEqual(range?.lowerBound, day(-ScoreRowFinalization.maxRecomputeDays))
    }

    /// Review focus 5: a clock moved backwards leaves finalizedThrough in the future.
    func test_finalizedThroughInTheFuture_nothingDue() {
        XCTAssertNil(ScoreRowFinalization.recomputeRange(finalizedThrough: day(5), now: Date()))
    }

    /// The finalized marker is a calendar day; a time-of-day on it must not shift the range.
    func test_finalizedThroughWithTimeOfDay_usesItsCalendarDay() {
        let lateOnDayMinus4 = day(-3).addingTimeInterval(-60)
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: lateOnDayMinus4, now: Date())
        XCTAssertEqual(range, day(-3)...day(-1))
    }

    // MARK: - Marker advance (R1)

    /// The foreground refresh runs after the Strava sync, so what it recomputed is final.
    func test_markerAdvance_foregroundThatReadHealthKit_advancesToTheRangeEnd() {
        let range = day(-3)...day(-1)
        XCTAssertEqual(ScoreRowFinalization.markerAdvance(range: range, readBiometrics: true, advancesMarker: true), day(-1))
    }

    /// The background pass may have seen only the HealthKit copy of yesterday's ride; the
    /// Strava copy (power, zones) arrives with the next foreground sync. Advancing here
    /// would freeze yesterday at the HealthKit-only load forever.
    func test_markerAdvance_backgroundPass_neverAdvances() {
        let range = day(-3)...day(-1)
        XCTAssertNil(ScoreRowFinalization.markerAdvance(range: range, readBiometrics: true, advancesMarker: false))
    }

    /// A locked device or missing permission read nothing: those days stay due.
    func test_markerAdvance_nothingRead_doesNotAdvance() {
        XCTAssertNil(ScoreRowFinalization.markerAdvance(range: day(-3)...day(-1), readBiometrics: false, advancesMarker: true))
    }

    func test_markerAdvance_nothingDue_doesNotAdvance() {
        XCTAssertNil(ScoreRowFinalization.markerAdvance(range: nil, readBiometrics: true, advancesMarker: true))
    }

    // MARK: - What counts as having read HealthKit (R4)

    /// Users with no sleep tracking still have HRV or RHR. Requiring sleep kept their
    /// marker unset forever, so every run recomputed the whole horizon.
    func test_readBiometrics_hrvOrRestingHeartRateIsEnough_sleepIsNotRequired() {
        XCTAssertTrue(ScoreRowFinalization.readBiometrics(hrvCount: 5, restingHRCount: 0))
        XCTAssertTrue(ScoreRowFinalization.readBiometrics(hrvCount: 0, restingHRCount: 5))
        XCTAssertFalse(ScoreRowFinalization.readBiometrics(hrvCount: 0, restingHRCount: 0))
    }
}
