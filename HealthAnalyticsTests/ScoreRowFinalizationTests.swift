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

    func test_neverFinalized_recomputesYesterdayOnly() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: nil, now: Date())
        XCTAssertEqual(range, day(-1)...day(-1))
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
}
