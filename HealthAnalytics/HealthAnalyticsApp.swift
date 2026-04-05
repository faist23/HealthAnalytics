//
//  HealthAnalyticsApp.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI
import Combine
import SwiftData
import BackgroundTasks

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
                        await PatternNotificationService.shared.requestAuthorizationIfNeeded()
                    }
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
            }
        }
        .modelContainer(HealthDataContainer.shared)
        .backgroundTask(.appRefresh("com.craigfaist.HealthAnalytics.patternAnalysis")) {
            let container = HealthDataContainer.shared
            let analyzer = TrainingDNAAnalyzer(modelContainer: container)
            let preference = HRVSourcePreference(
                rawValue: UserDefaults.standard.string(forKey: "preferredHRVSource") ?? HRVSourcePreference.auto.rawValue
            ) ?? .auto
            if let historyDays = try? await analyzer.analyze(sourcePreference: preference) {
                UserDefaults.standard.set(historyDays, forKey: "healthKitHistoryDays")
                UserDefaults.standard.set(Date(), forKey: "lastPatternAnalysisDate")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isOnboardingComplete {
                Task {
                    #if DEBUG
                    print("🔄 App became active, triggering smart sync...")
                    #endif
                    // ✅ CHANGED: Use smart sync instead of global sync
                    await SyncManager.shared.performSmartSync()
                }
            }
            if newPhase == .background && isOnboardingComplete {
                schedulePatternAnalysisTask()
            }
        }
    }
    
    private func schedulePatternAnalysisTask() {
        let request = BGProcessingTaskRequest(identifier: "com.craigfaist.HealthAnalytics.patternAnalysis")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleIncomingURL(_ url: URL) {
        #if DEBUG
        print("📱 Received URL: \(url.absoluteString)")
        print("📱 Scheme: \(url.scheme ?? "none")")
        print("📱 Host: \(url.host ?? "none")")
        #endif

        // Handle Strava OAuth callback
        if url.scheme == "healthanalytics" {
            Task {
                do {
                    try await StravaManager.shared.handleOAuthCallback(url: url)
                    #if DEBUG
                    print("✅ Successfully handled Strava callback")
                    #endif

                    // After successful Strava auth, sync to get Strava activities
                    await SyncManager.shared.performSmartSync()
                } catch {
                    #if DEBUG
                    print("❌ Error handling Strava callback: \(error)")
                    #endif
                }
            }
        }
    }
}
