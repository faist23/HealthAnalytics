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
        XCTAssertEqual(tab, TabCoordinator.recoveryTab)
        XCTAssertNil(pattern)
    }

    func testNavigateToIntelligenceWithPattern() async {
        let (tab, pattern) = await MainActor.run {
            let c = TabCoordinator()
            c.navigate(to: TabCoordinator.intelligenceTab, scrollTo: .hrvPrecursor)
            return (c.selectedTab, c.pendingScrollPattern)
        }
        XCTAssertEqual(tab, TabCoordinator.intelligenceTab)
        XCTAssertEqual(pattern, .hrvPrecursor)
    }

    func testNavigateWithNilPattern() async {
        let (tab, pattern) = await MainActor.run {
            let c = TabCoordinator()
            c.navigate(to: TabCoordinator.intelligenceTab, scrollTo: nil)
            return (c.selectedTab, c.pendingScrollPattern)
        }
        XCTAssertEqual(tab, TabCoordinator.intelligenceTab)
        XCTAssertNil(pattern)
    }

    func testNavigateTwiceOverwritesFirst() async {
        let pattern = await MainActor.run {
            let c = TabCoordinator()
            c.navigate(to: TabCoordinator.intelligenceTab, scrollTo: .performancePeak)
            c.navigate(to: TabCoordinator.intelligenceTab, scrollTo: .tapering)
            return c.pendingScrollPattern
        }
        XCTAssertEqual(pattern, .tapering)
    }
}
