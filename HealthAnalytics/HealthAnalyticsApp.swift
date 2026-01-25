//
//  HealthAnalyticsApp.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI

@main
struct HealthAnalyticsApp: App {
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false
    
    var body: some Scene {
        WindowGroup {
            if isOnboardingComplete {
                ContentView()
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
            }
        }
    }
}
