//
//  PatternNotificationService.swift
//  HealthAnalytics
//
//  Phase 2 — Pattern Engine
//  UNUserNotificationCenter wrapper. One notification per pattern type, ever.
//

import Foundation
import UserNotifications

actor PatternNotificationService {
    static let shared = PatternNotificationService()
    private init() {}

    // MARK: - Permission

    /// Called once at app launch. Silently skips on denial — no retry.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do { try await center.requestAuthorization(options: [.alert, .sound]) } catch {}
    }

    // MARK: - Dispatch

    /// Sends a notification for each pattern where notificationSent == false.
    /// Sets notificationSent = true on each sent pattern.
    /// Caller is responsible for calling modelContext.save() after this returns.
    func notifyIfNew(_ patterns: [TrainingPattern]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        for pattern in patterns where !pattern.notificationSent {
            let bodyText = body(for: pattern.patternType)
            guard !bodyText.isEmpty else {
                // Pattern types with empty body (e.g. .tapering) are planning tools —
                // intentionally suppressed from user notification.
                pattern.notificationSent = true
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = "Training DNA found"
            content.body = bodyText
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "trainingDNA.\(pattern.patternType.rawValue)",
                content: content,
                trigger: nil
            )

            try? await center.add(request)
            pattern.notificationSent = true
        }
    }

    private func body(for type: PatternType) -> String {
        switch type {
        case .blockCrashCycle:
            return "You consistently overreach in week 3 of your training blocks. Open the app to see the pattern."
        case .hrvPrecursor:
            return "Your HRV drops 36–72h before illness — you have a detectable warning signature."
        case .sleepFragmentation:
            return "Your sleep fragments after sustained high training loads. Open the app to see the pattern."
        case .backToBackCrash:
            return "Your recovery drops predictably after back-to-back hard sessions. Open the app to see your pattern."
        case .performancePeak:
            return "You're in peak form \u{1F3C5} — great week for a race or benchmark effort."
        case .tapering:
            return ""  // Tapering never dispatches a notification (planning tool, not a surprise insight)
                       // Case required for exhaustive switch compliance only.
        }
    }
}
