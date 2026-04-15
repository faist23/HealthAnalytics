//
//  WorkoutMatcher.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import HealthKit

struct WorkoutMatcher {
    
    /// Matches HealthKit workouts with Strava activities to avoid double-counting
    /// Prioritizes workouts with power data when deduplicating
    static func deduplicateWorkouts(
        healthKitWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> (healthKitOnly: [WorkoutData], stravaOnly: [StravaActivity], matched: [(WorkoutData, StravaActivity)]) {
        
        var healthKitOnly: [WorkoutData] = []
        var stravaOnly: [StravaActivity] = []
        var matched: [(WorkoutData, StravaActivity)] = []
        
        var unmatchedStrava = stravaActivities
        
        for hkWorkout in healthKitWorkouts {
            // Try to find a matching Strava activity
            if let matchIndex = findMatchingStravaActivity(
                for: hkWorkout,
                in: unmatchedStrava
            ) {
                let stravaActivity = unmatchedStrava[matchIndex]
                matched.append((hkWorkout, stravaActivity))
                unmatchedStrava.remove(at: matchIndex)
            } else {
                healthKitOnly.append(hkWorkout)
            }
        }
        
        stravaOnly = unmatchedStrava
        
        #if DEBUG
        print("🔍 Workout Matching Results:")
        print("   HealthKit only: \(healthKitOnly.count)")
        print("   Strava only: \(stravaOnly.count)")
        print("   Matched: \(matched.count)")
        #endif
        
        return (healthKitOnly, stravaOnly, matched)
    }
    
    /// Returns the best workout from a matched pair based on data quality
    /// Prioritizes: 1) Power data, 2) HR data, 3) Strava (usually more detailed)
    static func selectBestWorkout(
        from match: (healthKit: WorkoutData, strava: StravaActivity)
    ) -> WorkoutSource {
        
        let hkHasPower = false // HealthKit doesn't typically have power for our use case
        let stravaHasPower = match.strava.averageWatts != nil
        
        // Priority 1: Power data
        if stravaHasPower && !hkHasPower {
            return .strava(match.strava)
        }
        
        // Priority 2: If both or neither have power, prefer Strava (more detailed metrics)
        return .strava(match.strava)
    }
    
    enum WorkoutSource {
        case healthKit(WorkoutData)
        case strava(StravaActivity)
        
        var duration: TimeInterval {
            switch self {
            case .healthKit(let workout): return workout.duration
            case .strava(let activity): return Double(activity.movingTime)
            }
        }
        
        var hasPowerData: Bool {
            switch self {
            case .healthKit: return false
            case .strava(let activity): return activity.averageWatts != nil
            }
        }
    }
    
    /// Finds a matching Strava activity for a HealthKit workout
    private static func findMatchingStravaActivity(
        for hkWorkout: WorkoutData,
        in stravaActivities: [StravaActivity]
    ) -> Int? {
        let hkEnd = hkWorkout.startDate.addingTimeInterval(hkWorkout.duration)

        for (index, stravaActivity) in stravaActivities.enumerated() {
            guard let stravaStartDate = stravaActivity.startDateFormatted else { continue }

            // 1. Activity type matching
            guard activityTypesMatch(hkType: hkWorkout.workoutType, stravaType: stravaActivity.type) else { continue }

            // 2. Overlap check (same rationale as findMatch above)
            let stravaEnd = stravaStartDate.addingTimeInterval(Double(stravaActivity.movingTime))
            let overlapStart = max(hkWorkout.startDate, stravaStartDate)
            let overlapEnd   = min(hkEnd, stravaEnd)
            guard overlapStart < overlapEnd else { continue }

            let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
            let minDuration     = min(hkWorkout.duration, Double(stravaActivity.movingTime))
            guard overlapDuration >= minDuration * 0.5 else { continue }

            return index
        }

        return nil
    }
    
    /// Checks if HealthKit workout type matches Strava activity type
    private static func activityTypesMatch(hkType: HKWorkoutActivityType, stravaType: String) -> Bool {
        switch hkType {
        case .running:
            return stravaType == "Run"
        case .cycling:
            return stravaType == "Ride" || stravaType == "VirtualRide"
        case .swimming:
            return stravaType == "Swim"
        case .walking:
            return stravaType == "Walk"
        case .hiking:
            return stravaType == "Hike"
        case .rowing:
            return stravaType == "Rowing"
        case .yoga:
            return stravaType == "Yoga"
        default:
            // For other types, do a string comparison
            return hkType.name.lowercased().contains(stravaType.lowercased()) ||
            stravaType.lowercased().contains(hkType.name.lowercased())
        }
    }
    
    nonisolated static func findMatch(for hkWorkout: WorkoutData, in stravaImports: [StravaImportData]) -> StravaImportData? {
        let hkEnd = hkWorkout.startDate.addingTimeInterval(hkWorkout.duration)

        for stravaActivity in stravaImports {
            // 1. Activity type matching
            guard activityTypesMatch(hkType: hkWorkout.workoutType, stravaType: stravaActivity.workoutType) else { continue }

            // 2. Overlap check.
            // HealthKit records elapsed time (start = button press); Strava records moving time
            // (start = first GPS movement, often 5-15 min later). The Strava window is typically
            // fully contained within the HK window. A start-time or duration comparison alone
            // misses these. Instead, require ≥50% of the shorter session to overlap.
            let stravaEnd = stravaActivity.startDate.addingTimeInterval(stravaActivity.duration)
            let overlapStart = max(hkWorkout.startDate, stravaActivity.startDate)
            let overlapEnd   = min(hkEnd, stravaEnd)
            guard overlapStart < overlapEnd else { continue }

            let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
            let minDuration     = min(hkWorkout.duration, stravaActivity.duration)
            guard overlapDuration >= minDuration * 0.5 else { continue }

            return stravaActivity
        }
        return nil
    }

    // helper to compare two HKWorkoutActivityTypes directly
    nonisolated private static func activityTypesMatch(hkType: HKWorkoutActivityType, stravaType: HKWorkoutActivityType) -> Bool {
        return hkType == stravaType
    }
}

// Helper extension to get activity name
extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .rowing: return "Rowing"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Weight Training"
        default: return "Workout"
        }
    }
    
    var iconName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .coreTraining: return "figure.core.training"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .traditionalStrengthTraining: return "figure.strengthtraining.functional"
       default: return "figure.mixed.cardio"
        }
    }
}
