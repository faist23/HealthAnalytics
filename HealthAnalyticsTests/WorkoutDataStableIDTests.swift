//
//  WorkoutDataStableIDTests.swift
//  HealthAnalyticsTests
//
//  Verifies WorkoutData.stableID deterministically maps StoredWorkout.id → WorkoutData.id.
//  This is the fix for the intent-label join bug: Strava ids (numeric strings) previously
//  produced a fresh random UUID on every conversion, so they never matched persisted data.
//

import XCTest
import HealthKit
@testable import HealthAnalytics

final class WorkoutDataStableIDTests: XCTestCase {

    // MARK: - HealthKit ids (already UUID strings) pass through unchanged

    func testHealthKitUUIDStringPassesThroughUnchanged() {
        let hkId = UUID().uuidString
        let derived = WorkoutData.stableID(from: hkId)

        // For HK workouts, id.uuidString must still equal originalId so existing joins hold.
        XCTAssertEqual(derived.uuidString, hkId)
    }

    func testLowercaseUUIDStringStillParsesToSameUUID() {
        let upper = "6BA7B814-9DAD-11D1-80B4-00C04FD430C8"
        XCTAssertEqual(
            WorkoutData.stableID(from: upper),
            WorkoutData.stableID(from: upper.lowercased())
        )
    }

    // MARK: - Strava ids (numeric strings) are deterministic

    func testStravaIdIsDeterministicAcrossCalls() {
        let stravaId = "12345678901"
        let first = WorkoutData.stableID(from: stravaId)
        let second = WorkoutData.stableID(from: stravaId)

        XCTAssertEqual(first, second, "Same Strava id must always derive the same UUID")
    }

    func testDifferentStravaIdsProduceDifferentUUIDs() {
        let a = WorkoutData.stableID(from: "12345678901")
        let b = WorkoutData.stableID(from: "12345678902")

        XCTAssertNotEqual(a, b)
    }

    func testStableIDViaConversionMatchesDirectDerivation() {
        // The id assigned during StoredWorkout → WorkoutData conversion must equal the
        // deterministic derivation, and originalId must carry the raw stored id.
        let stored = StoredWorkout(
            id: "99887766554",
            type: .cycling,
            startDate: Date(),
            duration: 3600,
            distance: 30000,
            power: 200,
            energy: 600,
            hr: 140,
            source: "strava"
        )
        let workout = WorkoutData(from: stored)

        XCTAssertEqual(workout.id, WorkoutData.stableID(from: "99887766554"))
        XCTAssertEqual(workout.originalId, "99887766554")
    }

    // MARK: - Derived value is a well-formed RFC 4122 v5 UUID

    func testDerivedUUIDHasVersion5AndCorrectVariant() {
        let uuid = WorkoutData.stableID(from: "strava-activity-42")
        let bytes = uuid.uuid

        // Version nibble (high nibble of byte 6) must be 5.
        XCTAssertEqual(bytes.6 >> 4, 0x5, "UUID version must be 5")
        // Variant: top two bits of byte 8 must be 10 (RFC 4122).
        XCTAssertEqual(bytes.8 >> 6, 0b10, "UUID must use the RFC 4122 variant")
    }

    // MARK: - Known-answer vector (locks the namespace + algorithm)

    func testKnownAnswerVectorIsStable() {
        // If this fails, the namespace UUID or the v5 algorithm changed — which would re-key
        // every derived workout UUID. Update deliberately, never incidentally.
        // Reference computed independently via Python's uuid.uuid5 with the same namespace.
        let uuid = WorkoutData.stableID(from: "12345678901")
        XCTAssertEqual(uuid.uuidString, "1B60F3C8-DD61-5E3B-9D7B-4112435B2973",
                       "Regenerate this vector only when intentionally changing the derivation")
    }
}
