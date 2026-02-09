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
                        // ✅ CHANGED: Use smart sync instead of global sync
                        await SyncManager.shared.performSmartSync()
                    }
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
            }
        }
        .modelContainer(HealthDataContainer.shared)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isOnboardingComplete {
                Task {
                    print("🔄 App became active, triggering smart sync...")
                    // ✅ CHANGED: Use smart sync instead of global sync
                    await SyncManager.shared.performSmartSync()
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
                    
                    // After successful Strava auth, sync to get Strava activities
                    await SyncManager.shared.performSmartSync()
                } catch {
                    print("❌ Error handling Strava callback: \(error)")
                }
            }
        }
    }
}
