//
//  HealthAnalyticsApp.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI
import Combine
import SwiftData

@main
struct HealthAnalyticsApp: App {
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            if isOnboardingComplete {
                MainTabView()
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
                    .task {
                        // Trigger sync on first launch
                        await SyncManager.shared.performGlobalSync()
                    }
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
            }
        }
        // Use the shared container from your HealthDataContainer.swift file
        .modelContainer(HealthDataContainer.shared)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isOnboardingComplete {
                Task {
                    print("🔄 App became active, triggering sync...")
                    await SyncManager.shared.performGlobalSync()
                }
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
