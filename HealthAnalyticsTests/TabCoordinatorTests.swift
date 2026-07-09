//
//  TabCoordinatorTests.swift
//  HealthAnalyticsTests
//

import XCTest
@testable import HealthAnalytics

final class TabCoordinatorTests: XCTestCase {

    func testInitialState() async {
        let (tab, pattern) = await MainActor.run {
            let c = TabCoordinator()
            return (c.selectedTab, c.pendingScrollPattern)
        }
        XCTAssertEqual(tab, TabCoordinator.coachTab)
        XCTAssertNil(pattern)
    }

    func testIntelligenceTabAliasTracksPatternsTab() {
        XCTAssertEqual(TabCoordinator.intelligenceTab, TabCoordinator.patternsTab,
            "intelligenceTab alias must track patternsTab until removed after v0.2.0")
    }

    func testNavigateToPatternsWithPattern() async {
        let (tab, pattern) = await MainActor.run {
            let c = TabCoordinator()
            c.navigate(to: TabCoordinator.patternsTab, scrollTo: .hrvPrecursor)
            return (c.selectedTab, c.pendingScrollPattern)
        }
        XCTAssertEqual(tab, TabCoordinator.patternsTab)
        XCTAssertEqual(pattern, .hrvPrecursor)
    }

    func testNavigateWithNilPattern() async {
        let (tab, pattern) = await MainActor.run {
            let c = TabCoordinator()
            c.navigate(to: TabCoordinator.patternsTab, scrollTo: nil)
            return (c.selectedTab, c.pendingScrollPattern)
        }
        XCTAssertEqual(tab, TabCoordinator.patternsTab)
        XCTAssertNil(pattern)
    }

    func testNavigateTwiceOverwritesFirst() async {
        let pattern = await MainActor.run {
            let c = TabCoordinator()
            c.navigate(to: TabCoordinator.patternsTab, scrollTo: .performancePeak)
            c.navigate(to: TabCoordinator.patternsTab, scrollTo: .tapering)
            return c.pendingScrollPattern
        }
        XCTAssertEqual(pattern, .tapering)
    }
}
