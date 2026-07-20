//
//  SwiftDataConversions.swift
//  HealthAnalytics
//
//  Conversion extensions for SwiftData models
//

import Foundation
import HealthKit
import CryptoKit

// MARK: - WorkoutData Conversion

extension WorkoutData {
    init(from stored: StoredWorkout) {
        self.init(
            id: WorkoutData.stableID(from: stored.id),
            originalId: stored.id,
            title: stored.title,
            workoutType: stored.workoutType,
            startDate: stored.startDate,
            endDate: stored.startDate.addingTimeInterval(stored.duration),
            duration: stored.duration,
            totalEnergyBurned: stored.totalEnergyBurned,
            totalDistance: stored.distance,
            averagePower: stored.averagePower,
            normalizedPower: stored.normalizedPower,
            powerZoneSeconds: stored.powerZoneSeconds,
            averageHeartRate: stored.averageHeartRate,
            source: stored.source.lowercased() == "strava" ? .strava : (stored.source.lowercased() == "applewatch" ? .appleWatch : .other)
        )
    }

    /// Deterministically map a `StoredWorkout.id` to the `WorkoutData.id` UUID.
    ///
    /// HealthKit ids already ARE UUID strings, so they pass through unchanged and
    /// `id.uuidString == originalId` continues to hold for those workouts. Strava ids are
    /// numeric strings (e.g. "12345678901") — the old `UUID(uuidString:) ?? UUID()` minted a
    /// fresh random UUID for every conversion, so a Strava workout's `id` was unstable across
    /// runs and never matched anything persisted under its real id. We now derive a stable
    /// RFC 4122 v5 (name-based, SHA-1) UUID from the id, so the same workout always maps to the
    /// same UUID. `originalId` remains the authoritative key for joins against stored data.
    static func stableID(from storedId: String) -> UUID {
        if let uuid = UUID(uuidString: storedId) {
            return uuid
        }
        return uuidV5(namespace: workoutIDNamespace, name: storedId)
    }

    /// Fixed namespace UUID for workout id derivation (app-specific, never changes —
    /// changing it would re-key every derived UUID).
    private static let workoutIDNamespace = UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!

    /// RFC 4122 §4.3 version-5 UUID: SHA-1 of (namespace bytes ‖ name), with the version and
    /// variant bits overwritten per spec.
    private static func uuidV5(namespace: UUID, name: String) -> UUID {
        var hasher = Insecure.SHA1()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(name.utf8))
        var bytes = Array(hasher.finalize().prefix(16))

        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant

        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - DailyNutrition Conversion

extension DailyNutrition {
    init(from stored: StoredNutrition) {
        self.init(
            date: stored.date,
            totalCalories: stored.calories,
            totalProtein: stored.protein,
            totalCarbs: stored.carbs,
            totalFat: stored.fat,
            totalFiber: nil,
            totalSugar: nil,
            totalWater: nil,
            breakfast: nil,
            lunch: nil,
            dinner: nil,
            snacks: nil
        )
    }
}
