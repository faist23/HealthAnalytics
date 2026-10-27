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
import UIKit

@main
struct HealthAnalyticsApp: App {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist (pinned by
    /// `BackgroundRefreshConfigTests`); a mismatch makes `submit` throw silently.
    nonisolated static let patternAnalysisTaskID = "com.craigfaist.HealthAnalytics.patternAnalysis"
    nonisolated static let patternAnalysisMinBackgroundInterval: TimeInterval = 6 * 3600

    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false
    @StateObject private var tabCoordinator = TabCoordinator()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if isOnboardingComplete {
                MainTabView()
                    .environmentObject(tabCoordinator)
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
                    .task {
                        ReadinessRepository.shared.bootstrap()
                        // A background app-refresh launch can connect the scene too. Leave sync,
                        // the Coach refresh and the permission prompt to `.active`: run locked,
                        // HealthKit refuses reads and the day's Coach would be cached from nothing.
                        guard ReadinessRepository.applicationIsInForeground() else { return }
                        await SyncManager.shared.performSmartSync()
                        await ReadinessRepository.shared.refreshIfNecessary(
                            modelContext: HealthDataContainer.shared.mainContext
                        )
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
        .backgroundTask(.appRefresh(Self.patternAnalysisTaskID)) {
            // Keep the chain going: iOS runs each request once, and otherwise the next one
            // is only submitted when the user next leaves the app.
            Self.schedulePatternAnalysisTask()
            // HealthKit refuses reads while the device is locked; don't spend the refresh
            // budget on a run that can only fail.
            guard await MainActor.run(body: { UIApplication.shared.isProtectedDataAvailable }) else { return }
            // Same path as the foreground (the throttle is stamped only when patterns were
            // actually refreshed). Finishing in the background it stays silent on errors and
            // skips the Coach refresh — see `ReadinessRepository.isAppInForeground`. On budget expiry the handler stops
            // waiting; the run resumes next time the app is awake.
            await ReadinessRepository.shared.runPatternAnalysis(container: HealthDataContainer.shared, trigger: .background)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isOnboardingComplete {
                Task {
                    #if DEBUG
                    print("🔄 App became active, triggering smart sync...")
                    #endif
                    await SyncManager.shared.performSmartSync()
                    await ReadinessRepository.shared.refreshIfNecessary(
                        modelContext: HealthDataContainer.shared.mainContext
                    )
                    // Here too: a scene connected by a background launch skipped it in `.task`.
                    await PatternNotificationService.shared.requestAuthorizationIfNeeded()
                }
            }
            if newPhase == .background && isOnboardingComplete {
                Task { await Self.schedulePatternAnalysisTaskIfNoneIsPending() }
            }
        }
    }
    
    /// Leaving the app schedules a run only when none is pending. A submit replaces the
    /// pending request, so resubmitting on every exit would push the run 6h out each time
    /// and someone who opens the app more often than that would never get one.
    nonisolated private static func schedulePatternAnalysisTaskIfNoneIsPending() async {
        let pending = await BGTaskScheduler.shared.pendingTaskRequests()
        guard !pending.contains(where: { $0.identifier == patternAnalysisTaskID }) else { return }
        schedulePatternAnalysisTask()
    }

    /// Nonisolated: called from the `.backgroundTask` action, which is not on the main actor.
    nonisolated private static func schedulePatternAnalysisTask() {
        // Must be an app-refresh request to match the SwiftUI `.appRefresh` handler, and
        // needs UIBackgroundModes `fetch` in Info.plist — without it submit throws.
        let request = BGAppRefreshTaskRequest(identifier: patternAnalysisTaskID)
        // Patterns move over days and stay active for 10; a few runs a day keeps them
        // alive and notifications timely without spending the refresh budget.
        request.earliestBeginDate = Date(timeIntervalSinceNow: patternAnalysisMinBackgroundInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("⚠️ Pattern analysis background task not scheduled: \(error)")
            #endif
        }
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
                    await ReadinessRepository.shared.refreshIfNecessary(
                        modelContext: HealthDataContainer.shared.mainContext
                    )
                } catch {
                    #if DEBUG
                    print("❌ Error handling Strava callback: \(error)")
                    #endif
                }
            }
        }
    }
}
