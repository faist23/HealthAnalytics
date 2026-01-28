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
        
        print("🔍 Workout Matching Results:")
        print("   HealthKit only: \(healthKitOnly.count)")
        print("   Strava only: \(stravaOnly.count)")
        print("   Matched: \(matched.count)")
        
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
        
        for (index, stravaActivity) in stravaActivities.enumerated() {
            // Check if activities match based on:
            // 1. Start time (within 5 minutes)
            // 2. Activity type
            // 3. Duration (within 10% or 2 minutes)
            
            guard let stravaStartDate = stravaActivity.startDateFormatted else { continue }
            
            // 1. Time matching (within 5 minutes = 300 seconds)
            let timeDifference = abs(hkWorkout.startDate.timeIntervalSince(stravaStartDate))
            guard timeDifference <= 300 else { continue }
            
            // 2. Activity type matching
            guard activityTypesMatch(hkType: hkWorkout.workoutType, stravaType: stravaActivity.type) else { continue }
            
            // 3. Duration matching (within 10% or 120 seconds, whichever is larger)
            let durationDifference = abs(hkWorkout.duration - Double(stravaActivity.movingTime))
            let durationTolerance = max(hkWorkout.duration * 0.1, 120.0)
            guard durationDifference <= durationTolerance else { continue }
            
            // Found a match!
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
}
