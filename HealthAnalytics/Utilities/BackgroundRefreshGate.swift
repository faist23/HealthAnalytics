//
//  BackgroundRefreshGate.swift
//  HealthAnalytics
//
//  Serializes the background pass's HealthKit-only workout upsert with the foreground
//  sync. Each upsert checks the store for the other's copy of a ride before inserting
//  (Strava twin skip, HealthKit dedup), so two in flight at once can both miss and store
//  the ride twice.
//

import Foundation

/// Owned by `SyncManager` (main actor). Both checks run on the main actor before their
/// first await, so a background refresh and a foreground sync can't interleave: a
/// refresh arriving while a sync runs is skipped, and a sync starting while a refresh
/// runs waits for it.
@MainActor
final class BackgroundRefreshGate {
    private var inFlight: Task<Void, Error>?

    /// Runs `work` unless a foreground sync is running (`isSyncing`), in which case it
    /// does nothing and returns false — the sync is storing that window with the Strava
    /// copies. A refresh requested while another is in flight joins it.
    @discardableResult
    func run(skippingWhile isSyncing: Bool, _ work: @escaping @MainActor () async throws -> Void) async throws -> Bool {
        guard !isSyncing else { return false }
        if let inFlight {
            try await inFlight.value
            return true
        }
        let task = Task { [weak self] in
            // Cleared from inside the task, at completion, so a sync can't wait on a
            // finished refresh and a later refresh never joins one.
            defer { self?.inFlight = nil }
            try await work()
        }
        inFlight = task
        try await task.value
        return true
    }

    /// Returns once any in-flight background refresh has finished, failed or not.
    func waitForInFlight() async {
        _ = try? await inFlight?.value
    }
}
