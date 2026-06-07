//
//  TabCoordinator.swift
//  HealthAnalytics
//

import Combine

final class TabCoordinator: ObservableObject {
    // Tab indices must match the .tag(N) values in MainTabView.swift.
    // v0.1.9.0 Intelligence redesign: Intelligence renamed → Patterns and a new
    // Labs tab added as the 5th surface for experimental features. patternsTab
    // and intelligenceTab are intentional aliases — both point at tag 3 so
    // existing call sites (RecoveryTabView's pattern deep-link) keep working
    // without churn. The intelligenceTab alias can be removed once we're
    // confident there are no external consumers.
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
