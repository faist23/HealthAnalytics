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

    /// Called at launch and on every foreground activation; a no-op once the user has
    /// answered. Silently skips on denial — no retry.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do { try await center.requestAuthorization(options: [.alert, .sound]) } catch {}
    }

    // MARK: - Dispatch

    /// Whether alerts can be delivered. Patterns are marked sent only when this is true,
    /// so a user who grants permission later still gets them.
    func isAuthorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Sends one notification per pattern type. The caller marks and saves
    /// `notificationSent` first (see `TrainingDNAAnalyzer.analyze`), so this never
    /// touches SwiftData models. Types with an empty body (e.g. `.tapering`) are planning
    /// tools and are intentionally not delivered.
    func send(_ types: [PatternType]) async {
        let center = UNUserNotificationCenter.current()
        for type in types {
            let bodyText = body(for: type)
            guard !bodyText.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Training DNA found"
            content.body = bodyText
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "trainingDNA.\(type.rawValue)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
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
