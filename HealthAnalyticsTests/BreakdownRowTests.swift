//
//  BreakdownRowTests.swift
//  HealthAnalyticsTests
//

import XCTest
@testable import HealthAnalytics

/// P4: the score breakdown bar never draws outside its track.
final class BreakdownRowTests: XCTestCase {
    // Value: protects=the bar fill stays within 0...1 for out-of-range scores and a zero max;
    //   fails_when=the clamp is removed (overflowing bar, invalid negative frame width);
    //   why_new=P4 TODO; seam=none (pure static); no_claim=layout
    func test_fillFraction_isClamped() {
        XCTAssertEqual(BreakdownRow.fillFraction(score: 20, maxScore: 40), 0.5)
        XCTAssertEqual(BreakdownRow.fillFraction(score: 55, maxScore: 40), 1)
        XCTAssertEqual(BreakdownRow.fillFraction(score: -3, maxScore: 40), 0)
        XCTAssertEqual(BreakdownRow.fillFraction(score: 5, maxScore: 0), 0)
    }
}
