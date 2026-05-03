//
//  TabCoordinator.swift
//  HealthAnalytics
//

import SwiftUI
import Combine

final class TabCoordinator: ObservableObject {
    static let recoveryTab     = 0
    static let strainTab       = 1
    static let sleepTab        = 2
    static let healthspanTab   = 3
    static let intelligenceTab = 4

    @Published var selectedTab: Int = TabCoordinator.recoveryTab
    @Published var pendingScrollPattern: PatternType? = nil

    func navigate(to tab: Int, scrollTo pattern: PatternType?) {
        selectedTab = tab
        pendingScrollPattern = pattern
    }
}
