//
//  TabCoordinatorTests.swift
//  HealthAnalyticsTests
//

import XCTest
@testable import HealthAnalytics

@MainActor
final class TabCoordinatorTests: XCTestCase {

    func testInitialState() {
        let coordinator = TabCoordinator()
        XCTAssertEqual(coordinator.selectedTab, TabCoordinator.recoveryTab)
        XCTAssertNil(coordinator.pendingScrollPattern)
    }

    func testNavigateToIntelligenceWithPattern() {
        let coordinator = TabCoordinator()
        coordinator.navigate(to: TabCoordinator.intelligenceTab, scrollTo: .hrvPrecursor)
        XCTAssertEqual(coordinator.selectedTab, TabCoordinator.intelligenceTab)
        XCTAssertEqual(coordinator.pendingScrollPattern, .hrvPrecursor)
    }

    func testNavigateWithNilPattern() {
        let coordinator = TabCoordinator()
        coordinator.navigate(to: TabCoordinator.intelligenceTab, scrollTo: nil)
        XCTAssertEqual(coordinator.selectedTab, TabCoordinator.intelligenceTab)
        XCTAssertNil(coordinator.pendingScrollPattern)
    }

    func testNavigateTwiceOverwritesFirst() {
        let coordinator = TabCoordinator()
        coordinator.navigate(to: TabCoordinator.intelligenceTab, scrollTo: .performancePeak)
        coordinator.navigate(to: TabCoordinator.intelligenceTab, scrollTo: .tapering)
        XCTAssertEqual(coordinator.pendingScrollPattern, .tapering)
    }
}
