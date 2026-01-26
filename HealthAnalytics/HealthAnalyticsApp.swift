//
//  HealthAnalyticsApp.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI
import Combine

@main
struct HealthAnalyticsApp: App {
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false
    
    var body: some Scene {
        WindowGroup {
            if isOnboardingComplete {
                MainTabView()
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
            }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        print("📱 Received URL: \(url.absoluteString)")
        print("📱 Scheme: \(url.scheme ?? "none")")
        print("📱 Host: \(url.host ?? "none")")
        
        // Handle Strava OAuth callback
        if url.scheme == "healthanalytics" {
            Task {
                do {
                    try await StravaManager.shared.handleOAuthCallback(url: url)
                    print("✅ Successfully handled Strava callback")
                } catch {
                    print("❌ Error handling Strava callback: \(error)")
                }
            }
        }
    }
}
