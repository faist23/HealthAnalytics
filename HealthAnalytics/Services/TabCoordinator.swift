//
//  TabCoordinator.swift
//  HealthAnalytics
//

import Combine

final class TabCoordinator: ObservableObject {
    // Tab indices must match the .tag(N) values in MainTabView.swift.
    // v0.1.9.0 Intelligence redesign: Intelligence renamed → Patterns and a new
    // Labs tab added as the 5th surface for experimental features. patternsTab
    // and intelligenceTab are intentional aliases — both point at tag 3. No
    // in-repo call sites reference intelligenceTab anymore; it is retained
    // solely for the CLAUDE.md deprecation window (remove after v0.2.0).
    static let coachTab        = 0
    static let readinessTab    = 1
    static let loadTab         = 2
    static let patternsTab     = 3
    static let intelligenceTab = 3 // alias — deprecate after one release cycle
    static let labsTab         = 4

    @Published var selectedTab: Int = TabCoordinator.coachTab
    @Published var pendingScrollPattern: PatternType? = nil

    func navigate(to tab: Int, scrollTo pattern: PatternType?) {
        selectedTab = tab
        pendingScrollPattern = pattern
    }
}
