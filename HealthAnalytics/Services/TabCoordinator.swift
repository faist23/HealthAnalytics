//
//  TabCoordinator.swift
//  HealthAnalytics
//

import Combine

final class TabCoordinator: ObservableObject {
    // Tab indices must match the .tag(N) values in MainTabView.swift.
    // Stale constants (sleepTab=2, healthspanTab=3, intelligenceTab=4) were left
    // over from a pre-redesign IA; intelligenceTab=4 pointed at a tag that
    // doesn't exist, so coordinator.navigate(to: .intelligenceTab, ...) fell
    // back to tag 0 (Coach) instead of landing on Intelligence.
    static let coachTab        = 0
    static let readinessTab    = 1
    static let loadTab         = 2
    static let intelligenceTab = 3

    @Published var selectedTab: Int = TabCoordinator.coachTab
    @Published var pendingScrollPattern: PatternType? = nil

    func navigate(to tab: Int, scrollTo pattern: PatternType?) {
        selectedTab = tab
        pendingScrollPattern = pattern
    }
}
