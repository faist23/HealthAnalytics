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
            let content = UNMutableNotificationContent()
            content.title = "Training DNA found"
            content.body = body(for: pattern.patternType)
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
        }
    }
}
