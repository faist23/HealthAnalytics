//
//  StoredFTPSnapshot.swift
//  HealthAnalytics
//
//  Persists time-stamped FTP values so that historical workout intensity can be
//  evaluated against the FTP that was in effect on the day of the workout,
//  not the current FTP.
//
//  Fetch semantics: resolvedFTP(for:snapshots:) returns the most recent snapshot
//  whose date ≤ workoutDate — i.e., the FTP that was active on that day.
//

import Foundation
import SwiftData

@Model
final class StoredFTPSnapshot {
    var date: Date      // effective-from date (Strava fetch date, or user-entered)
    var watts: Int
    var source: String  // "strava_profile" | "manual"

    init(date: Date, watts: Int, source: String) {
        self.date = date
        self.watts = watts
        self.source = source
    }
}

extension StoredFTPSnapshot {
    /// Insert a new snapshot for the Strava sync path.
    /// Deduplicates within the same calendar day: skips if today already has a snapshot
    /// with the same watts. Allows FTP to return to a prior value (e.g. 250→230→250)
    /// since different days are always independent.
    /// Also writes to UserDefaults["strava_ftp"] to keep the legacy display path working.
    @discardableResult
    static func upsertIfChanged(watts: Int, source: String, context: ModelContext) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        var descriptor = FetchDescriptor<StoredFTPSnapshot>(
            predicate: #Predicate<StoredFTPSnapshot> { $0.date >= today && $0.date < tomorrow }
        )
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []

        if let snapshot = existing.first {
            // Same calendar day — update in place to avoid duplicate rows
            if snapshot.watts == watts { return false }
            snapshot.watts = watts
            snapshot.source = source
        } else {
            context.insert(StoredFTPSnapshot(date: today, watts: watts, source: source))
        }
        try? context.save()

        // Keep UserDefaults in sync for the legacy FTP display in StravaConnectionView
        UserDefaults.standard.set(watts, forKey: "strava_ftp")
        return true
    }

    /// FTP that was in effect on `workoutDate`.
    /// Returns the most recent snapshot whose date ≤ workoutDate, or 200W if none exists.
    static func resolved(for workoutDate: Date, snapshots: [StoredFTPSnapshot]) -> Double {
        snapshots
            .filter { $0.date <= workoutDate }
            .max(by: { $0.date < $1.date })
            .map { Double($0.watts) } ?? 200.0
    }

    /// Sendable-safe overload for use across async boundaries.
    /// Accepts value-type tuples instead of @Model objects — avoids Sendable violations in nonisolated async contexts.
    static func resolved(for workoutDate: Date, ftpValues: [(date: Date, watts: Int)]) -> Double {
        ftpValues
            .filter { $0.date <= workoutDate }
            .max(by: { $0.date < $1.date })
            .map { Double($0.watts) } ?? 200.0
    }
}
